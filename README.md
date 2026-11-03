
# wss-py-wrapper

Python wrapper around the HFI_WSS_Interface .NET library using `pythonnet`.

This repository is the reusable wrapper/library repo. It is intended to be consumed directly as a Python package or included from another repository as a git submodule.

All documentation about the API and related implementations can be found in [GitHub Pages](https://cwru-non-academic.github.io/WSS_Documentation/).

## Repository Layout

- `src/wss_py_wrapper/`: Python package source
- `docs/`: Sphinx documentation config
- `Config/`: default configuration assets bundled with the repo
- `Cs_Libraries/`: canonical bundled .NET runtime dependencies and WSS DLLs

## Install

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
python -m pip install -r requirements.txt
python -m pip install -e .
```

## Runtime Prerequisites

- Python 3.9+
- The bundled `Cs_Libraries/` directory must be present in the repository

DLL discovery walks upward looking for `Cs_Libraries/` from the package location. Keeping `Cs_Libraries/` in this repository makes the repo self-contained when used as a submodule.

## Library Usage

```python
from pathlib import Path

from wss_py_wrapper import StimulationController, WssConfig


config = WssConfig.default(Path(__file__))
controller = StimulationController(config)
controller.Initialize()

controller.StartStimulation()
controller.StimWithMode("index", 0.25)
controller.StopStimulation()

controller.Shutdown()
```

## Submodule Usage

In an application repo, add this repository as a submodule and install it from the submodule path:

```bash
git submodule add <repo-url> external/wss-py-wrapper
python -m pip install -r external/wss-py-wrapper/requirements.txt
python -m pip install -e external/wss-py-wrapper
```

The application repo should own its CLI and other app-specific orchestration, while importing `WssConfig` and `StimulationController` from this package.

## Development

Formatting/lint/type-check:

```bash
python -m pip install -U ruff mypy
python -m ruff format src
python -m ruff check src
python -m mypy src/wss_py_wrapper
```

Build docs:

```bash
python -m pip install -e ".[docs]"
sphinx-build -b html docs docs/_build/html
```

Build package:

```bash
python -m pip install -U build
python -m build
```

## Conformance and automatic dependency promotion

See [.github/PYTHON_AUTOMATION.md](.github/PYTHON_AUTOMATION.md) for canonical tests, CI checks, artifact provenance, dev promotion and human merge gates.
# Explicit BLE transport

Serial remains the default. To select a packaged BLE backend, construct
`WssConfig(..., transport="ble", ble_device_name="WSS")`, use
`ble_device_id="..."`, or explicitly set `ble_auto=True`. Then use the existing
controller initialization/lifecycle. Do not combine BLE selection with Serial,
Test or Conformance options. The exact legacy distribution does not provide a
macOS BLE backend; the new declared distribution requires both its managed backend
and universal native bridge. See [.github/MACOS_BLE_RECEIVER.md](.github/MACOS_BLE_RECEIVER.md).

## BLE platform loading and device configuration

BLE is selected explicitly through the existing Core transport factory. Provide
an exact nonblank name, device ID, or `ble_auto=True`; whitespace-only targets are
rejected before loading or connecting. Nonblank names are preserved exactly.
On macOS use a compatible CoreCLR runtime (for example,
`PYTHONNET_RUNTIME=coreclr`) and retain both
`backends/macos/WSS.Transport.BLE.MacOS.dll` and its paired universal
`libwss_macos_ble.dylib`. Missing declared assets fail platform validation.
Windows, Linux and macOS select their own backend; the loader never substitutes
another platform's backend.

The platform checks verify installed-wheel loading and actual BLE constructor
routing. macOS CI additionally checks native exports/ABI and creates/disposes an
inert native context. They do not scan, connect to a device, or demonstrate
physical stimulation. The shared ten-case canonical suite uses Core's emulator
and unchanged validators. Real device, permissions and radio behavior require
separate manual validation on the target OS.

`Config/stimConfig.json` now exposes existing Core receiver settings:
`broadcastTarget: "0x8F"` and `wssTargets: ["0x81", "0x82", "0x83"]`. These
are receiver addresses, not a configurable host sender byte. Existing user files
are not replaced; legacy files use the historical defaults, and custom addresses
such as Wss1 `"0x80"` remain supported. Keep hardware-specific firmware and
calibration settings. Stop and reconstruct/reinitialize the controller after
changing addresses so Core creates a new address map; `LoadCoreConfigFile()` alone
does not rebuild it.

`Initialize()` starts asynchronous device setup; it does not establish readiness.
Use `Ready()`/`Started()` and the resolved `WssConfig.log_path` for diagnostics.
Core errors and Python tick failures already flow through the file sink. Config
and DLL paths belong to the consuming application; pass explicit paths when
using an installed wheel outside the source/submodule layout.

## Staged dev application fan-out

The receiver declaration in `.github/dev-propagation.json` participates in Core's
integration barrier. A merged dependency PR whose verified Core producer commit
contains `tools/ci/dev-propagation.json` waits without application write tokens.
Legacy immediate fan-out is retained only when that file is absent from the
complete, verified producer commit tree; API errors or unknown policies fail.

Core resumes the registered main workflow with `producer_run_id`,
`barrier_run_id` and `barrier_attempt`. Trusted Core main tooling runs
`verify-barrier` before the existing approval, parent/payload, normal-CI and
application dispatch validators, and again immediately before a write token.
No live settings, credentials, payloads or dependency pins are changed by these
hooks. Both branches need the receiver declaration and workflow before a staged
Core producer can freeze its plan. A real staged resume remains an integration
check after deployment; ordinary PR CI alone does not prove live fan-out.
