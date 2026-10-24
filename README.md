
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

