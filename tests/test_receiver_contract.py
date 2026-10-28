"""Protect declaration/architecture boundaries without pretending to load a dylib."""
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "conformance"))
from platform_smoke import verify_macos_inventory
from wss_py_wrapper import WssConfig


class ReceiverContractTests(unittest.TestCase):
    def test_declared_backend_requires_both_assets_and_both_architectures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertFalse(verify_macos_inventory(root, "legacy-v1"))
            with self.assertRaises(RuntimeError):
                verify_macos_inventory(root, "macos-ble-v1")
            mac = root / "backends/macos"
            mac.mkdir(parents=True)
            (mac / "WSS.Transport.BLE.MacOS.dll").write_bytes(b"fixture; not activation proof")
            native = mac / "libwss_macos_ble.dylib"
            data = bytearray(160)
            struct.pack_into(">II", data, 0, 0xCAFEBABE, 2)
            for index, (cpu, offset) in enumerate(((0x01000007, 64), (0x0100000C, 112))):
                struct.pack_into(">IIIII", data, 8 + index * 20, cpu, 0, offset, 32, 0)
                struct.pack_into("<II", data, offset, 0xFEEDFACF, cpu)
            native.write_bytes(data)
            self.assertTrue(verify_macos_inventory(root, "macos-ble-v1"))
            with self.assertRaises(RuntimeError):
                verify_macos_inventory(root, "legacy-v1")
            struct.pack_into(">I", data, 8 + 20, 0x01000007)
            native.write_bytes(data)
            with self.assertRaises(RuntimeError):
                verify_macos_inventory(root, "macos-ble-v1")
            native.write_bytes(b"not a Mach-O image")
            with self.assertRaises(RuntimeError):
                verify_macos_inventory(root, "macos-ble-v1")

    def test_ble_selection_requires_an_explicit_target_and_preserves_serial_default(self):
        paths = dict(config_path=Path("Config"), log_path=Path("unused.log"), cs_lib_dir=Path("Cs_Libraries"))
        self.assertEqual(WssConfig(**paths).transport, "serial")
        self.assertEqual(WssConfig(**paths, transport="ble", ble_device_name="target").transport, "ble")
        self.assertTrue(WssConfig(**paths, transport="ble", ble_auto=True).ble_auto)
        for options in ({"transport": "ble"}, {"ble_device_name": "target"},
                        {"transport": "ble", "ble_auto": True, "test_mode": True},
                        {"transport": "ble", "ble_auto": True, "serial_port": "COM1"}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                WssConfig(**paths, **options)
