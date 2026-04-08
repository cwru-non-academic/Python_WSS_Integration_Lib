# Agent Guidance (wss-py-wrapper)
This repository is a Python wrapper around a C#/.NET interface (HFI_WSS_Interface) using `pythonnet`.

Rules discovery: no Cursor rules (`.cursor/rules/` or `.cursorrules`) and no Copilot rules (`.github/copilot-instructions.md`) exist in this repo.

## Repo Layout
- Package source: `src/wss_py_wrapper/`
- Public API exports: `src/wss_py_wrapper/__init__.py`
- Interop core: `src/wss_py_wrapper/stimulation_controller.py`
- Bundled runtime assets: `Cs_Libraries/` and `Config/`
- Packaging: `pyproject.toml` (setuptools)

## Setup

Create a virtualenv and install the package editable:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
python -m pip install -e .
```

Runtime prerequisites:
- A `Cs_Libraries/` directory containing the required `.dll` files must exist at or above the package directory.
- DLL discovery walks upward looking for `Cs_Libraries/` (see `wss_py_wrapper.config._find_cs_libraries_dir`).

## Build / Run / Test Commands

Build wheel/sdist (requires the `build` package):

```bash
python -m pip install -U build
python -m build
```

Sanity import:

```bash
python -c "import wss_py_wrapper; print('ok')"
```

Lint/format/type-check (optional; not configured in-repo):

```bash
python -m pip install -U ruff mypy
python -m ruff format src
python -m ruff check src
python -m mypy src/wss_py_wrapper
```

Tests:
- There is currently no `tests/` directory and no `pytest` configuration.
- If you add pytest tests, these are the expected commands agents should use:

```bash
python -m pip install -U pytest
pytest
pytest tests/test_controller.py
pytest tests/test_controller.py::test_initialize
pytest -k initialize
```

Typical agent workflow (when making changes):

```bash
python -m ruff format src
python -m ruff check src
python -c "import wss_py_wrapper; print('ok')"
```

If you touch packaging/release artifacts, also verify a clean build:

```bash
python -m build
```

## Coding Conventions

### Imports
- Put `from __future__ import annotations` at the top of new modules (most existing modules already do).
- Import grouping: standard library, third-party, then local (`from .x import y`), with a blank line between groups.
- Keep pythonnet/.NET imports inside functions when they are optional or environment-dependent.

### Formatting
- PEP 8, 4-space indents.
- Prefer parentheses for wrapping long expressions; avoid `\\` line continuations.
- Prefer f-strings for messages.

### Types
- Target Python >= 3.9 (see `pyproject.toml`).
- Prefer `X | None` and builtin generics (`list[str]`, `dict[str, int]`).
- Add return types for public functions/methods.
- For pythonnet/.NET imports, keep `# type: ignore` on the import line (do not blanket-ignore entire modules).

### Naming (Interop Matters)
This wrapper intentionally mirrors C# naming in the public surface.

- Keep existing public names as-is (many are PascalCase to match .NET: `StartStimulation`, `BasicSupported`).
- New internal helpers: `snake_case` and prefixed with `_`.
- Do not rename exported API without a migration strategy (downstream breakage risk).

### Error Handling
- It is acceptable to catch broad `Exception` at interop/probing boundaries (e.g. locating .NET types) and in background threads.
- In normal Python logic, do not swallow exceptions; raise specific exceptions:
  - `RuntimeError` for invalid lifecycle usage (e.g. using controller before `Initialize()`)
  - `ValueError` for invalid inputs (e.g. bad channel/finger)
  - `FileNotFoundError` for missing DLLs/config

### .NET / pythonnet Interop
- Keep module import-time side effects minimal; prefer doing interop work inside `Initialize()`/`_load_dotnet()`.
- When supporting multiple .NET namespaces/versions, probe in a clear order (see `_resolve_log_type()` and `_load_dotnet()`).
- Avoid over-typing .NET objects unless you can import the types safely in all supported environments.

DLL loading notes:
- `collect_dlls(...)` loads all `*.dll` under `Cs_Libraries/` and forces `WSS_Core_Interface.dll` to load last so dependencies resolve first.
- `WssLoader` attempts `pythonnet.load("netfx")` first, then falls back to `load()`.

### Logging
- Logging is primarily routed through a C# sink bridged to Python (`FileLogSink` + `install_csharp_log_sink`).
- When logging from Python into the C# logger, do it defensively (C# log type may be unavailable).

### Threading / Lifecycle
- `StimulationController` runs a background tick loop; keep start/stop idempotent and thread-safe.
- Guard shared state with `_gate` and avoid holding locks while doing slow interop calls when possible.
- Ensure `Shutdown()` stops the tick thread and disposes .NET objects defensively.

### Filesystem and Artifacts
- Use `pathlib.Path`.
- Do not commit runtime artifacts: `__pycache__/`, `*.pyc`, `*.log`, `*.egg-info/`, `.venv/`.

Note: this repo currently contains some runtime artifacts under `src/wss_py_wrapper/` (e.g. `__pycache__/`, `wss_*.log`). Do not add more; remove/ignore them if you are cleaning up.

## Change Discipline
- Keep this repo library-focused; CLI/app code belongs in the consuming application repo.
- Add new stable public APIs only if needed; when you do, export them via `src/wss_py_wrapper/__init__.py` and update `__all__`.
