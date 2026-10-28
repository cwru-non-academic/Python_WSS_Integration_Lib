"""Check the installed Python loader against the committed platform payload."""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys


def verify_macos_inventory(payload: Path, contract: str) -> bool:
    """Require both declared assets and both bounded 64-bit Mach-O slices."""
    managed = payload / "backends/macos/WSS.Transport.BLE.MacOS.dll"
    native = managed.with_name("libwss_macos_ble.dylib")
    if contract == "legacy-v1":
        if managed.exists() or native.exists():
            raise RuntimeError("Undeclared macOS backend in legacy payload")
        return False
    if not managed.is_file() or not native.is_file():
        raise RuntimeError("Declared macOS BLE backend/native bridge is missing")
    data = native.read_bytes()
    if len(data) < 48 or data[:4] != b"\xca\xfe\xba\xbe":
        raise RuntimeError("macOS bridge must be a universal Mach-O dylib")
    count = struct.unpack_from(">I", data, 4)[0]
    if count != 2:
        raise RuntimeError("macOS bridge must contain exactly x86_64 and arm64")
    slices = []
    for index in range(count):
        cpu, _, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + index * 20)
        if offset < 48 or size < 32 or offset + size > len(data):
            raise RuntimeError("Invalid macOS bridge slice bounds")
        if data[offset:offset + 4] != b"\xcf\xfa\xed\xfe" or struct.unpack_from("<I", data, offset + 4)[0] != cpu:
            raise RuntimeError("macOS bridge slice architecture mismatch")
        slices.append((cpu, offset, offset + size))
    if {item[0] for item in slices} != {0x01000007, 0x0100000C} or max(slices[0][1], slices[1][1]) < min(slices[0][2], slices[1][2]):
        raise RuntimeError("macOS bridge slices must be distinct x86_64/arm64 images")
    return True


def verify_macos_activation(payload: Path) -> None:
    """Check packaged C exports/ABI and CLR activation without radio commands."""
    path = payload / "backends/macos/libwss_macos_ble.dylib"
    library = ctypes.CDLL(str(path.resolve()))
    for name in ("wss_mac_abi", "wss_mac_create", "wss_mac_destroy", "wss_mac_submit", "wss_mac_cancel"):
        getattr(library, name)
    library.wss_mac_abi.restype = ctypes.c_uint32
    if library.wss_mac_abi() != 0x00010000:
        raise RuntimeError("Unexpected macOS BLE native ABI")
    callback_type = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_uint32,
                                    ctypes.c_uint64, ctypes.c_uint64, ctypes.c_int32,
                                    ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32)
    callback = callback_type(lambda *_: None)
    library.wss_mac_create.argtypes = [callback_type, ctypes.c_void_p]
    library.wss_mac_create.restype = ctypes.c_void_p
    library.wss_mac_destroy.argtypes = [ctypes.c_void_p]
    library.wss_mac_destroy.restype = None
    context = library.wss_mac_create(callback, None)
    if not context:
        raise RuntimeError("macOS BLE native context creation failed")
    library.wss_mac_destroy(context)  # Never submit initialize, discovery, connect or write.
    from Wss.Transports.Backends.MacOS import MacBleBackend

    MacBleBackend.VerifyNativeAbi()  # Prove CLR P/Invoke finds the same packaged bridge.


def verify_macos_managed(payload: Path) -> None:
    """Validate the declared managed identity/TFM on every host without a radio."""
    from wss_py_wrapper.wss_loader import WssLoader
    expected = (payload / "backends/macos/WSS.Transport.BLE.MacOS.dll").resolve()
    WssLoader([expected]).load()
    from Wss.Transports.Backends.MacOS import MacBleBackend
    import clr
    from System import Object
    from System.Runtime.Loader import AssemblyLoadContext

    assembly = clr.GetClrType(MacBleBackend).Assembly
    if (Path(assembly.Location).resolve() != expected or assembly.GetName().Name != "WSS.Transport.BLE.MacOS"
            or str(assembly.GetName().Version) != "1.0.0.0"
            or not Object.ReferenceEquals(AssemblyLoadContext.GetLoadContext(assembly), AssemblyLoadContext.Default)):
        raise RuntimeError("Wrong packaged macOS managed backend")
    framework = [a for a in assembly.GetCustomAttributesData()
                 if a.AttributeType.FullName == "System.Runtime.Versioning.TargetFrameworkAttribute"]
    if len(framework) != 1 or str(framework[0].ConstructorArguments[0].Value) != ".NETStandard,Version=v2.0":
        raise RuntimeError("Wrong macOS backend target framework")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", type=Path, required=True)
    parser.add_argument("--installed", type=Path, required=True)
    parser.add_argument("--cli", action="store_true")
    parser.add_argument("--contract", choices=("legacy-v1", "macos-ble-v1"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    macos_declared = verify_macos_inventory(args.payload, args.contract)
    import wss_py_wrapper
    from wss_py_wrapper.wss_loader import WssLoader, collect_dlls

    if not Path(wss_py_wrapper.__file__).resolve().is_relative_to(args.installed.resolve()):
        raise RuntimeError("Smoke check imported source instead of the installed wheel")
    WssLoader(collect_dlls(args.payload)).load()
    if macos_declared:
        verify_macos_managed(args.payload)
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
        if any(flag not in result.stdout for flag in ("--serial", "--cs-libs", "--ble-device-name", "--transport")):
            raise RuntimeError(f"Installed CLI help was incomplete: {result.stdout}")
        print("PASS: installed CLI argument parsing and help")
    ble_status = "unsupported: legacy payload does not declare macOS BLE"
    ble_routing = False
    if sys.platform != "darwin" or macos_declared:
        if args.cli:
            command = wss_cli.main
            parsed = command._build_parser().parse_args([
                "--transport", "ble", "--ble-device-name", "ci-load-only",
                "--cs-libs", str(args.payload)])
            config = command._config_from_args(parsed, args.installed)
            controller = command.create_controller(config)
        else:
            config = wss_py_wrapper.WssConfig(
                config_path=args.installed, log_path=args.installed / "unused.log",
                cs_lib_dir=args.payload, transport="ble", ble_device_name="ci-load-only")
            controller = wss_py_wrapper.StimulationController(config)
        controller._load_dotnet()
        transport = controller._create_transport()
        try:
            if transport.GetType().FullName != "Wss.Transports.BleNusTransport":
                raise RuntimeError("Production transport routing did not select BLE")
            from System import AppDomain

            platform, suffix = {"win32": ("windows", "Windows"), "linux": ("linux", "Linux"),
                                "darwin": ("macos", "MacOS")}[sys.platform]
            identity = f"WSS.Transport.BLE.{suffix}"
            loaded_backend = [a for a in AppDomain.CurrentDomain.GetAssemblies() if a.GetName().Name == identity]
            expected_backend = (args.payload / "backends" / platform / f"{identity}.dll").resolve()
            if len(loaded_backend) != 1 or Path(loaded_backend[0].Location).resolve() != expected_backend:
                raise RuntimeError("Facade did not activate the exact packaged BLE backend")
            if sys.platform == "darwin":
                verify_macos_activation(args.payload)
            ble_status = "passed: packaged facade/backend loaded; no radio commands"
            ble_routing = args.cli
        finally:
            transport.Dispose()
    args.output.write_text(json.dumps({"contract": args.contract, "macos_ble_declared": macos_declared,
                                      "ble": ble_status, "cli_routing": ble_routing,
                                      "physical_io": False}, indent=2))
    print(f"BLE: {ble_status}")
    print(f"PASS: installed Python loader selected {loaded}; Serial construction without opening hardware")


if __name__ == "__main__":
    main()
