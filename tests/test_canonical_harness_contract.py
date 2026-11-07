"""Canonical harness compatibility, without loading candidate assemblies."""
from pathlib import Path
import subprocess
import unittest


class CanonicalHarnessContractTests(unittest.TestCase):
    def test_reviewed_fixture_adapter_and_profiles(self):
        script = Path(__file__).with_name("canonical_harness_contract.ps1")
        result = subprocess.run(
            ["pwsh", "-NoProfile", "-File", str(script)],
            cwd=script.parent.parent,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: 11 source-only harness/profile checks", result.stdout)


if __name__ == "__main__":
    unittest.main()
