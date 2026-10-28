""".NET runtime and DLL loading helpers.

The wrapper loads a set of DLLs using :mod:`pythonnet` and then imports .NET types.
"""

from __future__ import annotations

from pathlib import Path
import os
import sys
from typing import Iterable


class WssLoader:
    """Load .NET DLL references via pythonnet.

    :param dll_paths: Iterable of DLL paths to add via ``clr.AddReference``.
    """

    def __init__(self, dll_paths: Iterable[Path]) -> None:
        self._dll_paths = [Path(p) for p in dll_paths]

    def load(self) -> None:
        """Load the WSS interface DLLs via pythonnet.

        This attempts to load a pythonnet runtime and then adds references for each
        path passed to the loader.
        """
        self._load_runtime()
        self._add_references(self._dll_paths)

    @staticmethod
    def _load_runtime() -> None:
        # An embedding .NET host already initialized clr. Loading another runtime
        # here would create incompatible managed object identities.
        if "clr" in sys.modules:
            return
        try:
            from pythonnet import get_runtime_info, load

            if get_runtime_info() is not None:
                return
        except Exception:
            load = None

        if load is None:
            return

        runtime = os.environ.get("PYTHONNET_RUNTIME")
        if runtime:
            load(runtime)
            return
        try:
            load("netfx")
        except Exception:
            try:
                load()
            except Exception:
                pass

    @staticmethod
    def _add_references(dll_paths: Iterable[Path]) -> None:
        import clr  # type: ignore
        from System import Environment  # type: ignore

        for dll in dll_paths:
            if dll.name == "System.IO.Ports.dll" and Environment.Version.Major >= 6:
                platform = "win" if os.name == "nt" else "unix"
                runtime_dll = (
                    dll.parent / "runtimes" / platform / "lib" / "net8.0" / dll.name
                )
                if runtime_dll.is_file():
                    dll = runtime_dll
            # pythonnet 3.0.5 appends .dll during path probing. Passing a Unix
            # absolute path with the suffix can instead be parsed as an assembly
            # name and throw before its full-path fallback is reached.
            clr.AddReference(str(dll.resolve().with_suffix("")))


def collect_dlls(cs_lib_dir: Path) -> list[Path]:
    """Collect ``.dll`` files from a ``Cs_Libraries`` directory.

    DLLs are returned in a stable order; the primary interface DLL
    (``WSS_Core_Interface.dll``) is forced to the end so dependencies are added
    first.

    Platform runtime assemblies are selected during loading; backend/native DLLs
    are left to their owning transport rather than passed to clr.AddReference.

    :param cs_lib_dir: Directory containing the managed entry assemblies.
    :returns: List of DLL paths.
    """
    if not cs_lib_dir.exists():
        return []

    dlls = [p for p in cs_lib_dir.glob("*.dll") if p.is_file()]
    dlls.sort(key=lambda p: p.name.lower())

    # Ensure the primary interface loads last so dependencies resolve first.
    primary = [p for p in dlls if p.name.lower() == "wss_core_interface.dll"]
    if primary:
        dlls = [p for p in dlls if p not in primary] + primary

    return dlls


def load_ble_backend(cs_lib_dir: Path) -> None:
    """Load the selected packaged BLE backend without initializing a radio.

    Python's application base is the Python installation, so explicitly load the
    backend beside this payload before the facade selects its shared factory.
    Native dependencies remain under the owning backend directory.
    """
    platform = {"win32": "windows", "linux": "linux", "darwin": "macos"}.get(sys.platform)
    if platform is None:
        raise RuntimeError(f"Unsupported BLE platform: {sys.platform}")
    names = {"windows": "Windows", "linux": "Linux", "macos": "MacOS"}
    directory = cs_lib_dir / "backends" / platform
    backend = directory / f"WSS.Transport.BLE.{names[platform]}.dll"
    if not backend.is_file():
        raise FileNotFoundError(f"Packaged {platform} BLE backend is missing: {backend}")
    if platform == "macos" and not (directory / "libwss_macos_ble.dylib").is_file():
        raise FileNotFoundError("Packaged macOS BLE native bridge is missing.")
    dependencies = sorted(p for p in directory.glob("*.dll")
                          if p != backend and p.name != "WssBleWindows.dll")
    WssLoader([*dependencies, backend]).load()
