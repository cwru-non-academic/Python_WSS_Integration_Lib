"""Exercise the Linux serial library lookup without opening a physical device."""

import os
from pathlib import Path
import platform
import subprocess
import sys
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / "Cs_Libraries"
NATIVE = PAYLOAD / "runtimes/linux-x64/native/libSystem.IO.Ports.Native.so"


@unittest.skipUnless(
    sys.platform == "linux" and platform.machine() == "x86_64" and NATIVE.is_file(),
    "requires the packaged Linux x64 serial runtime",
)
class SerialRuntimeTests(unittest.TestCase):
    def test_port_open_reaches_native_library_without_search_path(self):
        script = textwrap.dedent("""
            from pathlib import Path
            import sys
            import tempfile
            from wss_py_wrapper import StimulationController, WssConfig

            with tempfile.TemporaryDirectory(prefix="wss-missing-port-") as temp:
                config = Path(temp)
                port = Path("/dev") / config.name
                assert not port.exists()
                controller = StimulationController(WssConfig(
                    config_path=config, log_path=config / "host.log",
                    cs_lib_dir=Path(sys.argv[1]), serial_port=str(port),
                ))
                try:
                    controller.Initialize()
                except Exception as error:
                    from System import UnauthorizedAccessException
                    from System.IO import IOException
                    if not isinstance(error, (UnauthorizedAccessException, IOException)):
                        raise
                    assert str(port) in str(error), error
                else:
                    raise AssertionError(f"Unexpectedly opened {port}")
                finally:
                    controller.Shutdown()
        """)
        environment = {**os.environ, "PYTHONPATH": str(ROOT / "src"), "PYTHONNET_RUNTIME": "coreclr"}
        environment.pop("LD_LIBRARY_PATH", None)
        result = subprocess.run(
            [sys.executable, "-c", script, str(PAYLOAD)],
            env=environment, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
