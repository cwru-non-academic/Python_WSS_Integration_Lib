"""Public Python reload contract against the packaged Core emulator, never hardware."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
os.environ.setdefault("PYTHONNET_RUNTIME", "coreclr")
from wss_py_wrapper.config import WssConfig
from wss_py_wrapper.stimulation_controller import StimulationController


class ConfigurationReloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wss-python-reload-")
        self.root = Path(self.temp.name)
        self.write_profile(self.root)
        self.controller = StimulationController(WssConfig(
            config_path=self.root, log_path=self.root / "host.log",
            cs_lib_dir=Path(__file__).resolve().parents[1] / "Cs_Libraries",
            conformance_mode=True, tick_interval_ms=1))
        self.controller.Initialize()
        self.wait(self.controller.Started)

    def tearDown(self):
        self.controller.Shutdown()
        self.temp.cleanup()

    def wait(self, condition):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(.001)
        self.fail("Emulator did not observe requested state/output.")

    def output(self, operation, width, amplitude):
        trace = self.controller.GetConformance()
        baseline = max(x.SequenceNumber for x in trace.MessageHistory)
        operation()
        self.wait(lambda: any(x.SequenceNumber > baseline and x.Channel == 2 and
            x.PulseWidth == width and x.PulseAmplitude == amplitude and
            x.InterPulseInterval == 13 for x in trace.StimulationHistory))

    def test_model_calibration_and_bulk_amplitude_reach_wire_without_reset(self):
        trace = self.controller.GetConformance()
        self.write_profile(self.root, minimum=100, maximum=200, amplitude=4, gain=.5)
        self.controller.LoadParamsJson()
        self.assertEqual(trace, self.controller.GetConformance())
        self.output(lambda: self.controller.StimWithMode("ch2", .5), 125, 4)
        self.controller.UpdateChannelParams("ch2", 300, 100, 5)
        self.output(lambda: self.controller.StimulateNormalized("ch2", .5), 200, 5)
        self.controller.LoadParamsJson()
        self.output(lambda: self.controller.StimulateNormalized("ch2", .5), 200, 5)

    def test_profile_file_and_defaults_stop_old_stack_and_keep_startup_paths(self):
        original = self.controller.GetConformance()
        self.output(lambda: self.controller.StimulateNormalized("ch2", .5), 100, 2)
        profile = self.root / "profile with spaces"
        self.write_profile(profile, devices=2, minimum=100, maximum=200, amplitude=4, gain=.5)
        self.controller.LoadParamsJson(str(profile))
        self.wait(self.controller.Started)
        self.assertEqual(2, self.controller.GetCoreConfigCTRL().MaxWss)
        self.assertNotEqual(original, self.controller.GetConformance())
        final_output = [x for x in original.StimulationHistory if x.Channel == 2][-1]
        self.assertEqual(0, final_output.PulseWidth)
        self.assertEqual(0, final_output.PulseAmplitude)
        count = original.MessageHistory.Count
        self.output(lambda: self.controller.StimWithMode("ch2", .5), 125, 4)
        self.assertEqual(count, original.MessageHistory.Count)
        custom = profile / "specific parameters.json"
        custom.write_bytes((profile / "stimParams.json").read_bytes())
        self.controller.LoadParamsJson(str(custom))
        self.wait(self.controller.Started)
        self.assertEqual(1, self.controller.GetCoreConfigCTRL().MaxWss)
        self.output(lambda: self.controller.StimWithMode("ch2", .5), 150, 4)
        previous = Path.cwd()
        try:
            os.chdir(profile)
            self.controller.LoadParamsJson()
            self.output(lambda: self.controller.StimWithMode("ch2", .5), 100, 2)
        finally:
            os.chdir(previous)

    def test_core_reload_reconstructs_and_retains_calibration(self):
        original = self.controller.GetConformance()
        self.controller.UpdateChannelParams("ch2", 200, 100, 4)
        self.write_core(self.root, 2)
        self.controller.LoadCoreConfigFile()
        self.wait(self.controller.Started)
        self.assertNotEqual(original, self.controller.GetConformance())
        self.assertEqual(2, self.controller.GetCoreConfigCTRL().MaxWss)
        self.output(lambda: self.controller.StimulateNormalized("ch2", .5), 150, 4)

    def test_invalid_bundle_preserves_working_connection(self):
        original = self.controller.GetConformance()
        self.write_core(self.root, 2)
        (self.root / "modelConfig.json").write_text("invalid", encoding="utf-8")
        from System.IO import InvalidDataException
        with self.assertRaises(InvalidDataException):
            self.controller.LoadParamsJson()
        self.assertEqual(original, self.controller.GetConformance())
        self.assertEqual(1, self.controller.GetCoreConfigCTRL().MaxWss)
        self.output(lambda: self.controller.StimWithMode("ch2", .5), 100, 2)

    def test_failed_construction_retains_transport_until_cleanup_succeeds(self):
        snapshot = self.controller._current_snapshot()
        create_transport = self.controller._create_transport

        class CandidateTransport:
            disposals = 0
            def Dispose(self):
                self.disposals += 1
                if self.disposals == 1:
                    raise RuntimeError("injected cleanup failure")

        class SnapshotFailure:
            builds = 0
            def BuildAndInitialize(self, *args):
                self.builds += 1
                if self.builds == 1:
                    raise RuntimeError("injected construction failure")
                return snapshot.BuildAndInitialize(*args)
            def __getattr__(self, name):
                return getattr(snapshot, name)

        transport = CandidateTransport()
        request = SnapshotFailure()
        created = []
        def create():
            created.append(True)
            return transport if len(created) == 1 else create_transport()

        # Inject only at the factory boundary; retry/cleanup remains production code.
        self.controller._create_transport = create
        self.controller._pending_reload = request
        with self.assertRaisesRegex(RuntimeError, "construction failure"):
            self.controller.RetryReload()
        (self.root / "stimConfig.json").write_text("changed after staging", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "cleanup failure"):
            self.controller.RetryReload()
        self.assertFalse(self.controller.Started())
        self.assertEqual(1, len(created))
        self.controller.RetryReload()
        self.wait(self.controller.Started)
        self.assertEqual(2, transport.disposals)
        self.assertEqual(2, len(created))
        self.assertIsNone(self.controller.LastReloadError)
        self.output(lambda: self.controller.StimWithMode("ch2", .5), 100, 2)

    @staticmethod
    def write_core(directory, devices):
        (directory / "stimConfig.json").write_text(json.dumps({"maxWSS": devices,
            "firmware": "J03", "useConfigAmpCurves": True, "ampCurves": [{
            "LowThreshold": 0, "LowConst": 1, "ExpPower": 1,
            "LinearOffset": -1, "LinearSlope": 1}]}), encoding="utf-8")

    @classmethod
    def write_profile(cls, directory, devices=1, minimum=50, maximum=150, amplitude=2, gain=1):
        directory.mkdir(exist_ok=True)
        cls.write_core(directory, devices)
        channels = {str(ch): {"ampMode": "PW", "minPW": minimum, "maxPW": maximum,
            "defaultPA": amplitude, "IPI": 13} for ch in range(1, 10)}
        (directory / "stimParams.json").write_text(json.dumps({"stim": {"ch": channels}}), encoding="utf-8")
        (directory / "modelConfig.json").write_text(json.dumps({"calib": {"mode": "P"},
            "constants": {"PModeProportional": gain}}), encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
