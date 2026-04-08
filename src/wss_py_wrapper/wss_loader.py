""".NET runtime and DLL loading helpers.

The wrapper loads a set of DLLs using :mod:`pythonnet` and then imports .NET types.
"""

from __future__ import annotations

from pathlib import Path
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
        try:
            from pythonnet import load
        except Exception:
            load = None

        if load is None:
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

        for dll in dll_paths:
            clr.AddReference(str(dll))


def collect_dlls(cs_lib_dir: Path) -> list[Path]:
    """Collect ``.dll`` files from a ``Cs_Libraries`` directory.

    DLLs are returned in a stable order; the primary interface DLL
    (``WSS_Core_Interface.dll``) is forced to the end so dependencies are added
    first.

    :param cs_lib_dir: Directory to search recursively.
    :returns: List of DLL paths.
    """
    if not cs_lib_dir.exists():
        return []

    dlls = [p for p in cs_lib_dir.rglob("*.dll") if p.is_file()]
    dlls.sort(key=lambda p: p.name.lower())

    # Ensure the primary interface loads last so dependencies resolve first.
    primary = [p for p in dlls if p.name.lower() == "wss_core_interface.dll"]
    if primary:
        dlls = [p for p in dlls if p not in primary] + primary

    return dlls
