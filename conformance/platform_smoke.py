"""Check the installed Python loader against the committed platform payload."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", type=Path, required=True)
    parser.add_argument("--installed", type=Path, required=True)
    parser.add_argument("--cli", action="store_true")
    args = parser.parse_args()
    import wss_py_wrapper
    from wss_py_wrapper.wss_loader import WssLoader, collect_dlls

    if not Path(wss_py_wrapper.__file__).resolve().is_relative_to(args.installed.resolve()):
        raise RuntimeError("Smoke check imported source instead of the installed wheel")
    WssLoader(collect_dlls(args.payload)).load()
    from System.IO.Ports import SerialPort
    from Wss.Transports import SerialPortTransport, SerialPortTransportOptions

    options = SerialPortTransportOptions()
    options.PortName = "COM1" if os.name == "nt" else "/dev/ttyWssIntegrationSmoke"
    options.AutoSelectPort = False
    transport = SerialPortTransport(options)
    transport.Dispose()  # Construction only: never open/enumerate a physical port.
    import clr

    loaded = Path(clr.GetClrType(SerialPort).Assembly.Location).resolve()
    expected = (args.payload / "runtimes" / ("win" if os.name == "nt" else "unix")
                / "lib/net8.0/System.IO.Ports.dll").resolve()
    if loaded != expected or hashlib.sha256(loaded.read_bytes()).digest() != hashlib.sha256(expected.read_bytes()).digest():
        raise RuntimeError(f"Wrong Ports runtime loaded: {loaded}; expected {expected}")
    if clr.GetClrType(SerialPort).Assembly.GetName().Version.Major != 8:
        raise RuntimeError("Expected System.IO.Ports 8")
    if args.cli:
        import wss_cli.main

        if not Path(wss_cli.main.__file__).resolve().is_relative_to(args.installed.resolve()):
            raise RuntimeError("CLI smoke check imported source instead of the installed wheel")
        result = subprocess.run([sys.executable, "-m", "wss_cli.main", "--help"],
                                capture_output=True, text=True, timeout=30, check=True)
        if "--serial" not in result.stdout or "--cs-libs" not in result.stdout:
            raise RuntimeError(f"Installed CLI help was incomplete: {result.stdout}")
        print("PASS: installed CLI argument parsing and help")
    print(f"PASS: installed Python loader selected {loaded}; Serial construction without opening hardware")


if __name__ == "__main__":
    main()
