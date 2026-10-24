"""High-level controller wrapping the .NET stimulation stack.

This module contains the interop-heavy runtime core. The main entry point is
:class:`~wss_py_wrapper.stimulation_controller.StimulationController`.
"""

from __future__ import annotations

from pathlib import Path
import threading
import time

from .config import WssConfig
from .log_sink import FileLogSink, install_csharp_log_sink
from .wss_loader import WssLoader, collect_dlls


def _resolve_log_type():
    """Resolve the .NET ``Log`` type from supported namespaces.

    The wrapper supports multiple namespace layouts depending on the DLL set.

    :returns: A .NET type exposing ``SetSink``/``ResetSink`` and level methods.
    :raises RuntimeError: If no compatible Log type can be located.
    """
    try:
        from WSS_Core_Interface import Log as WssLog  # type: ignore

        return WssLog
    except Exception:
        pass

    try:
        from Wss.CoreModule import Log as WssLog  # type: ignore

        return WssLog
    except Exception:
        pass

    try:
        import Log as LogModule  # type: ignore

        if hasattr(LogModule, "Log"):
            return LogModule.Log
        return LogModule
    except Exception:
        pass

    raise RuntimeError("Unable to locate C# Log type in WSS_Core_Interface.dll.")


class StimulationController:
    """Python wrapper around the WSS .NET stimulation controller layers.

    Lifecycle:
    - Call :meth:`Initialize` before using any stimulation methods.
    - Call :meth:`Shutdown` to stop the background tick thread and dispose .NET objects.

    Threading:
    - A background tick loop calls ``Tick()`` at ``config.tick_interval_ms``.
    - Methods are guarded by an internal lock at key lifecycle transitions.

    :param config: Wrapper configuration.
    """

    def __init__(self, config: WssConfig) -> None:
        self._config = config
        self._gate = threading.Lock()
        self._wss = None
        self._basic_wss = None
        self._basic_supported = False
        self._tick_thread: threading.Thread | None = None
        self._tick_stop = threading.Event()
        self._log_reset = None
        self._log_type = None
        self._net_types = None
        self.started = False
        self._transport = None

    @property
    def BasicSupported(self) -> bool:
        """Whether the optional "Basic" .NET API is available."""
        return self._basic_supported

    def Initialize(self) -> None:
        """Load .NET DLLs, initialize layers, and start the tick loop.

        This method is safe to call multiple times; subsequent calls are no-ops
        once initialized.

        :raises FileNotFoundError: If required DLLs cannot be found.
        :raises RuntimeError: If required .NET types cannot be imported.
        """
        with self._gate:
            if self._wss is not None:
                return

            self._load_dotnet()
            self._install_log_sink()

            core = self._create_core()
            params_layer = self._net_types["StimParamsLayer"](
                core, str(self._config.config_path)
            )
            model_layer = self._net_types["ModelParamsLayer"](
                params_layer, str(self._config.config_path)
            )

            self._wss = model_layer
            self._basic_supported, self._basic_wss = self._try_get_basic(self._wss)

            self._wss.Initialize()
            self._ensure_tick_loop()

    def Shutdown(self) -> None:
        """Stop stimulation, stop the tick loop, and dispose .NET objects.

        Exceptions during shutdown are logged (when possible) but do not prevent
        the remainder of cleanup.
        """
        with self._gate:
            self._stop_tick_loop()
            if self._wss is not None:
                try:
                    self._wss.Shutdown()
                except Exception as ex:
                    self._log_error(f"Error during Shutdown: {ex}")
                try:
                    self._wss.Dispose()
                except Exception as ex:
                    self._log_error(f"Error disposing stimulation core: {ex}")

            if self._log_reset is not None:
                try:
                    self._log_reset()
                except Exception:
                    pass

            self._wss = None
            self._basic_wss = None
            self._basic_supported = False
            self._transport = None
            self.started = False

    def releaseRadio(self) -> None:
        """Backward-compatible alias for :meth:`Shutdown`."""
        self.Shutdown()

    def resetRadio(self) -> None:
        """Restart the .NET core without reloading DLLs.

        This shuts down and re-initializes the underlying .NET object and
        restarts the tick loop.
        """
        with self._gate:
            if self._wss is None:
                return
            self._stop_tick_loop()
            self._wss.Shutdown()
            self._wss.Initialize()
            self._ensure_tick_loop()

    def _ensure_tick_loop(self) -> None:
        if self._wss is None:
            return
        if self._tick_thread is not None and self._tick_thread.is_alive():
            return

        self._stop_tick_loop()
        self._tick_stop.clear()

        interval = max(1, int(self._config.tick_interval_ms))

        def loop() -> None:
            while not self._tick_stop.is_set():
                try:
                    if self._wss is not None:
                        self._wss.Tick()
                except Exception as ex:
                    self._log_error(f"Tick loop failure: {ex}")
                time.sleep(interval / 1000.0)

        self._tick_thread = threading.Thread(target=loop, name="wss-tick", daemon=True)
        self._tick_thread.start()

    def _stop_tick_loop(self) -> None:
        if self._tick_thread is None:
            return
        self._tick_stop.set()
        self._tick_thread.join(timeout=2)
        self._tick_thread = None

    def StimulateAnalog(
        self, finger: str, PW: int, amp: int = 3, IPI: int = 10
    ) -> None:
        """Send a direct analog stimulation request.

        :param finger: Finger name (e.g. ``"index"``) or channel alias (e.g. ``"ch2"``).
        :param PW: Pulse width (units defined by the .NET interface).
        :param amp: Amplitude (units defined by the .NET interface).
        :param IPI: Inter-pulse interval (units defined by the .NET interface).
        :raises RuntimeError: If called before :meth:`Initialize`.
        """
        wss = self._ensure_wss()
        channel = self._finger_to_channel(finger)
        wss.StimulateAnalog(channel, PW, amp, IPI)

    def StartStimulation(self) -> None:
        """Broadcast a start stimulation command.

        :raises RuntimeError: If called before :meth:`Initialize`.
        """
        wss = self._ensure_wss()
        wss.StartStim(self._net_types["WssTarget"].Broadcast)
        self.started = True

    def StopStimulation(self, targetWSS: int | None = None) -> None:
        """Broadcast a stop stimulation command.

        :raises RuntimeError: If called before :meth:`Initialize`.
        """
        wss = self._ensure_wss()
        wss.StopStim(self._int_to_wss_target(targetWSS))
        self.started = False

    def UpdateEventRatio(self, targetWSS: int, ratio: int, eventID: int) -> None:
        """Edit an event ratio through Core's pause/edit/resume boundary."""
        self._ensure_wss()
        basic = self._require_basic()
        if basic is None:
            raise RuntimeError("Basic stimulation not supported.")
        basic.UpdateEventRatio(ratio, eventID, self._int_to_wss_target(targetWSS))

    def GetConformance(self):
        """Return Core's evaluator for the explicitly selected emulator, or None."""
        if not self._config.conformance_mode or self._transport is None:
            return None
        return self._transport.Conformance

    def Save(self, targetWSS: int | None = None) -> None:
        basic = self._require_basic()
        if basic is None:
            return
        target = self._int_to_wss_target(targetWSS)
        basic.Save(target)

    def load(self, targetWSS: int | None = None) -> None:
        basic = self._require_basic()
        if basic is None:
            return
        target = self._int_to_wss_target(targetWSS)
        basic.Load(target)

    def request_Configs(self, targetWSS: int, command: int, id: int) -> None:
        basic = self._require_basic()
        if basic is None:
            return
        basic.Request_Configs(command, id, self._int_to_wss_target(targetWSS))

    def updateWaveform(self, *args) -> None:
        basic = self._require_basic()
        if basic is None:
            return

        if len(args) == 2 and isinstance(args[0], self._net_types["WaveformBuilder"]):
            waveform, event_id = args
            basic.UpdateWaveform(
                waveform, event_id, self._net_types["WssTarget"].Broadcast
            )
            return

        if (
            len(args) == 3
            and isinstance(args[0], int)
            and isinstance(args[1], self._net_types["WaveformBuilder"])
        ):
            target, waveform, event_id = args
            basic.UpdateWaveform(waveform, event_id, self._int_to_wss_target(target))
            return

        if len(args) == 2 and isinstance(args[0], (list, tuple)):
            waveform, event_id = args
            basic.UpdateWaveform(
                waveform, event_id, self._net_types["WssTarget"].Broadcast
            )
            return

        if (
            len(args) == 3
            and isinstance(args[0], int)
            and isinstance(args[1], (list, tuple))
        ):
            target, waveform, event_id = args
            basic.UpdateWaveform(waveform, event_id, self._int_to_wss_target(target))
            return

        if len(args) == 3 and all(isinstance(a, int) for a in args):
            cathodic, anodic, event_id = args
            basic.UpdateEventShape(
                cathodic, anodic, event_id, self._net_types["WssTarget"].Broadcast
            )
            return

        if len(args) == 4 and all(isinstance(a, int) for a in args):
            target, cathodic, anodic, event_id = args
            basic.UpdateEventShape(
                cathodic, anodic, event_id, self._int_to_wss_target(target)
            )
            return

        raise ValueError("Unsupported updateWaveform signature.")

    def loadWaveform(self, fileName: str, eventID: int) -> None:
        basic = self._require_basic()
        if basic is None:
            return
        basic.LoadWaveform(fileName, eventID)

    def WaveformSetup(self, wave, eventID: int, targetWSS: int | None = None) -> None:
        basic = self._require_basic()
        if basic is None:
            return
        target = self._int_to_wss_target(targetWSS)
        basic.WaveformSetup(wave, eventID, target)

    def UpdateIPD(self, ipd: int, eventID: int, targetWSS: int | None = None) -> None:
        basic = self._require_basic()
        if basic is None:
            return
        target = self._int_to_wss_target(targetWSS)
        basic.UpdateIPD(ipd, eventID, target)

    def StimulateNormalized(self, finger: str, magnitude: float) -> None:
        """Stimulate a channel with a normalized magnitude.

        :param finger: Finger name (e.g. ``"thumb"``) or channel alias (e.g. ``"ch1"``).
        :param magnitude: Normalized magnitude as defined by the .NET interface.
        :raises RuntimeError: If called before :meth:`Initialize`.
        """
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        wss.StimulateNormalized(ch, magnitude)

    def GetStimIntensity(self, finger: str) -> int:
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        return int(wss.GetStimIntensity(ch))

    def SaveParamsJson(self) -> None:
        """Persist stimulation parameters JSON via the .NET layer."""
        self._ensure_wss().SaveParamsJson()

    def LoadParamsJson(self, pathOrDir: str | None = None) -> None:
        """Load stimulation parameters JSON via the .NET layer.

        :param pathOrDir: Optional file/directory path interpreted by the .NET layer.
        """
        wss = self._ensure_wss()
        if pathOrDir is None:
            wss.LoadParamsJson()
        else:
            wss.LoadParamsJson(pathOrDir)

    def AddOrUpdateStimParam(self, key: str, value: float) -> None:
        self._ensure_wss().AddOrUpdateStimParam(key, value)

    def GetStimParam(self, key: str) -> float:
        return self._ensure_wss().GetStimParam(key)

    def TryGetStimParam(self, key: str):
        return self._ensure_wss().TryGetStimParam(key)

    def GetAllStimParams(self):
        return self._ensure_wss().GetAllStimParams()

    def SetChannelAmp(self, finger: str, mA: float) -> None:
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        wss.SetChannelAmp(ch, mA)

    def SetChannelPWMin(self, finger: str, us: int) -> None:
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        wss.SetChannelPWMin(ch, us)

    def SetChannelPWMax(self, finger: str, us: int) -> None:
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        wss.SetChannelPWMax(ch, us)

    def SetChannelIPI(self, finger: str, ms: int) -> None:
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        wss.SetChannelIPI(ch, ms)

    def GetChannelAmp(self, finger: str) -> float:
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        return wss.GetChannelAmp(ch)

    def GetChannelPWMin(self, finger: str) -> int:
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        return wss.GetChannelPWMin(ch)

    def GetChannelPWMax(self, finger: str) -> int:
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        return wss.GetChannelPWMax(ch)

    def GetChannelIPI(self, finger: str) -> int:
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        return wss.GetChannelIPI(ch)

    def IsFingerValid(self, finger: str) -> bool:
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        return wss.IsChannelInRange(ch)

    def StimWithMode(self, finger: str, magnitude: float) -> None:
        """Stimulate using the active mode/model parameters.

        :param finger: Finger name (e.g. ``"index"``) or channel alias (e.g. ``"ch2"``).
        :param magnitude: Normalized magnitude.
        """
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        wss.StimWithMode(ch, magnitude)

    def UpdateChannelParams(
        self, finger: str, max_val: int, min_val: int, amp: int
    ) -> None:
        """Update per-channel stimulation parameters.

        This writes values under keys like ``stim.ch.<ch>.maxPW``.

        :param finger: Finger name or channel alias.
        :param max_val: Maximum pulse width.
        :param min_val: Minimum pulse width.
        :param amp: Channel amplitude.
        :raises ValueError: If the channel is invalid for the current configuration.
        """
        wss = self._ensure_wss()
        ch = self._finger_to_channel(finger)
        if not wss.IsChannelInRange(ch):
            raise ValueError(f"Channel {ch} is not valid for current config.")

        base_key = f"stim.ch.{ch}"
        wss.AddOrUpdateStimParam(f"{base_key}.maxPW", max_val)
        wss.AddOrUpdateStimParam(f"{base_key}.minPW", min_val)
        wss.AddOrUpdateStimParam(f"{base_key}.amp", amp)

    def isModeValid(self) -> bool:
        return self._ensure_wss().IsModeValid()

    def Ready(self) -> bool:
        return self._wss.Ready() if self._wss is not None else False

    def Started(self) -> bool:
        return self._wss.Started() if self._wss is not None else False

    def GetModelConfigCTRL(self):
        return self._ensure_wss().GetModelConfigController()

    def GetCoreConfigCTRL(self):
        return self._ensure_wss().GetCoreConfigController()

    def LoadCoreConfigFile(self) -> None:
        """Reload the core configuration file via the .NET layer."""
        self._ensure_wss().LoadConfigFile()

    def _load_dotnet(self) -> None:
        dlls = collect_dlls(self._config.cs_lib_dir)
        if not dlls:
            raise FileNotFoundError(f"No DLLs found in {self._config.cs_lib_dir}")

        loader = WssLoader(dlls)
        loader.load()

        try:
            from Wss.CoreModule import (  # type: ignore
                CoreConfigController,
                WssStimulationCore,
                WssStimulationCoreOptions,
                WaveformBuilder,
                WssTarget,
            )
            from Wss.Transports import (  # type: ignore
                SerialPortTransport,
                SerialPortTransportOptions,
                TestModeTransport,
                TestModeTransportOptions,
            )
            from Wss.ModelModule import ModelConfigController, ModelParamsLayer  # type: ignore
            from Wss.CalibrationModule import StimParamsLayer  # type: ignore

            self._net_types = dict(
                CoreConfigController=CoreConfigController,
                WssStimulationCore=WssStimulationCore,
                WssStimulationCoreOptions=WssStimulationCoreOptions,
                WaveformBuilder=WaveformBuilder,
                WssTarget=WssTarget,
                SerialPortTransport=SerialPortTransport,
                SerialPortTransportOptions=SerialPortTransportOptions,
                TestModeTransport=TestModeTransport,
                TestModeTransportOptions=TestModeTransportOptions,
                ModelConfigController=ModelConfigController,
                ModelParamsLayer=ModelParamsLayer,
                StimParamsLayer=StimParamsLayer,
            )
            return
        except ImportError:
            pass

        try:
            from WSS_Core_Interface import (  # type: ignore
                CoreConfigController,
                ModelConfigController,
                ModelParamsLayer,
                TestModeTransport,
                StimParamsLayer,
                WaveformBuilder,
                WssStimulationCore,
                WssTarget,
            )
            from Wss.CoreModule import SerialPortTransport  # type: ignore
        except Exception:
            from Wss.CoreModule import (  # type: ignore
                CoreConfigController,
                TestModeTransport,
                WaveformBuilder,
                WssStimulationCore,
                WssTarget,
                SerialPortTransport,
            )
            from Wss.ModelModule import ModelConfigController, ModelParamsLayer  # type: ignore
            from Wss.CalibrationModule import StimParamsLayer  # type: ignore

        self._net_types = {
            "CoreConfigController": CoreConfigController,
            "ModelConfigController": ModelConfigController,
            "ModelParamsLayer": ModelParamsLayer,
            "SerialPortTransport": SerialPortTransport,
            "StimParamsLayer": StimParamsLayer,
            "TestModeTransport": TestModeTransport,
            "WaveformBuilder": WaveformBuilder,
            "WssStimulationCore": WssStimulationCore,
            "WssTarget": WssTarget,
        }

    def _create_core(self):
        transport = self._create_transport()
        self._transport = transport
        core_class = self._net_types["WssStimulationCore"]
        config_path = str(self._config.config_path)
        if "WssStimulationCoreOptions" in self._net_types:
            options = self._net_types["WssStimulationCoreOptions"]()
            options.ConfigPath = config_path
            options.MaxSetupTries = self._config.max_setup_tries
            return core_class(transport, options)
        return core_class(transport, config_path, self._config.max_setup_tries)

    def _create_transport(self):
        if self._config.conformance_mode:
            from Wss.Testing import EmulatedWssTransport  # type: ignore

            return EmulatedWssTransport()
        if self._config.test_mode:
            if "TestModeTransportOptions" in self._net_types:
                return self._net_types["TestModeTransport"](
                    self._net_types["TestModeTransportOptions"]()
                )
            return self._net_types["TestModeTransport"]()

        transport_class = self._net_types["SerialPortTransport"]
        if "SerialPortTransportOptions" in self._net_types:
            options = self._net_types["SerialPortTransportOptions"]()
            options.PortName = self._config.serial_port or ""
            options.AutoSelectPort = not bool(self._config.serial_port)
            return transport_class(options)
        if self._config.serial_port:
            return transport_class(self._config.serial_port)
        return transport_class()

    def _install_log_sink(self) -> None:
        if self._log_reset is not None:
            return
        self._log_type = _resolve_log_type()
        sink = FileLogSink(self._config.log_path)
        self._log_reset = install_csharp_log_sink(self._log_type, sink)

    def _log_error(self, message: str) -> None:
        if self._log_type is None:
            return
        try:
            self._log_type.Error(message)
        except Exception:
            pass

    def _ensure_wss(self):
        if self._wss is None:
            raise RuntimeError(
                "Call Initialize() before using the stimulation controller."
            )
        return self._wss

    def _try_get_basic(self, wss):
        try:
            result = wss.TryGetBasic()
        except Exception:
            return False, None

        if isinstance(result, tuple):
            success, basic = result
            return bool(success), basic

        return bool(result), None

    def _require_basic(self):
        if not self._basic_supported or self._basic_wss is None:
            self._log_error("Basic stimulation not supported.")
            return None
        return self._basic_wss

    def _int_to_wss_target(self, value: int | None):
        target = self._net_types["WssTarget"].Broadcast
        if value is None:
            return target
        if value == 1:
            return self._net_types["WssTarget"].Wss1
        if value == 2:
            return self._net_types["WssTarget"].Wss2
        if value == 3:
            return self._net_types["WssTarget"].Wss3
        return target

    @staticmethod
    def _finger_to_channel(finger_or_alias: str) -> int:
        if not finger_or_alias:
            return 0

        if finger_or_alias.lower().startswith("ch"):
            try:
                return int(finger_or_alias[2:])
            except ValueError:
                return 0

        match = finger_or_alias.lower()
        if match == "thumb":
            return 1
        if match == "index":
            return 2
        if match == "middle":
            return 3
        if match == "ring":
            return 4
        if match in ("pinky", "little"):
            return 5
        return 0
