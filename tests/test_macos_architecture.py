"""Architecture guards are policy tests; they do not claim native activation."""
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / "conformance/platform_smoke.py"
spec = importlib.util.spec_from_file_location("platform_smoke", path)
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class MacOSArchitectureTests(unittest.TestCase):
    def test_both_native_architectures_are_accepted(self):
        for arch, machine in (("x64", "x86_64"), ("arm64", "arm64")):
            with self.subTest(architecture=arch):
                self.assertEqual(smoke.require_native_architecture(
                    arch, machine, arch, arch, arch, False), arch)

    def test_each_mismatched_identity_is_rejected(self):
        valid = ["arm64", "arm64", "arm64", "arm64", "arm64", False]
        for index in range(1, 6):
            bad = valid.copy()
            bad[index] = True if index == 5 else "x64"
            with self.subTest(field=index):
                with self.assertRaises(RuntimeError):
                    smoke.require_native_architecture(*bad)

    def test_rosetta_cannot_count_as_native_intel(self):
        with self.assertRaises(RuntimeError):
            smoke.require_native_architecture("x64", "x86_64", "x64", "x64", "x64", True)

    def test_missing_or_unknown_expected_architecture_is_rejected(self):
        for expected in (None, "", "x86", "universal"):
            with self.subTest(expected=expected):
                with self.assertRaises(RuntimeError):
                    smoke.require_native_architecture(expected, "arm64", "arm64", "arm64", "arm64", False)


if __name__ == "__main__":
    unittest.main()
