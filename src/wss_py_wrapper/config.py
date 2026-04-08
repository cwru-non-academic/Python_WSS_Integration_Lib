"""Configuration helpers for the wrapper.

The main responsibility of this module is locating the ``Cs_Libraries/`` folder and
providing a small immutable configuration object used by :class:`~wss_py_wrapper.stimulation_controller.StimulationController`.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


def _find_cs_libraries_dir(start: Path) -> Path:
    """Search upward for a ``Cs_Libraries`` directory.

    :param start: Starting directory to probe.
    :returns: The first ``Cs_Libraries`` directory found when walking up parents.
    """
    for base in (start, *start.parents):
        candidate = base / "Cs_Libraries"
        if candidate.is_dir():
            return candidate
    return start / "Cs_Libraries"


def _default_log_path(main_file: Path) -> Path:
    """Return a default timestamped log path next to ``main_file``.

    :param main_file: File used as the naming anchor (typically a module file).
    :returns: A path like ``wss_YYYYMMDD_HHMMSS.log``.
    """
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return main_file.with_name(f"wss_{timestamp}.log")


@dataclass(frozen=True)
class WssConfig:
    """Configuration for :class:`~wss_py_wrapper.stimulation_controller.StimulationController`.

    :param config_path: Directory containing JSON configuration files consumed by the .NET layers.
    :param log_path: Path for the C# log sink output.
    :param cs_lib_dir: Directory containing WSS ``.dll`` files.
    :param serial_port: Optional fully-qualified serial device name; ``None`` enables auto-detect.
    :param test_mode: Whether to enable simulated transport.
    :param max_setup_tries: Maximum number of setup retries used by the .NET core.
    :param tick_interval_ms: Background tick interval in milliseconds.
    """

    config_path: Path
    log_path: Path
    cs_lib_dir: Path
    serial_port: str | None = None
    test_mode: bool = False
    max_setup_tries: int = 5
    tick_interval_ms: int = 10

    @classmethod
    def default(cls, main_file: Path) -> "WssConfig":
        """Create a default config using the current working directory.

        The returned config uses ``Path.cwd() / 'Config'`` for ``config_path`` and
        discovers ``cs_lib_dir`` by searching upward for ``Cs_Libraries/``.

        :param main_file: File used to anchor log naming and initial DLL search.
        :returns: A default configuration instance.
        """
        cs_lib_dir = _find_cs_libraries_dir(main_file.parent)
        return cls(
            config_path=Path.cwd() / "Config",
            log_path=_default_log_path(main_file),
            cs_lib_dir=cs_lib_dir,
        )
