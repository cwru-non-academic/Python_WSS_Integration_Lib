# Python WSS Integration Library

Use `wss_py_wrapper` to add WSS control to a Python application. For ready-made applications, see the [Python CLI](https://github.com/cwru-non-academic/CLI_Python_WSS_Application#readme) and [ROS 2 driver](https://github.com/cwru-non-academic/ROS_Python_WSS_Application#readme).

The [WSS documentation hub](https://cwru-non-academic.github.io/WSS_Documentation/) explains architecture, configuration, transport support, and lifecycle contracts.

## Prerequisites

- Git and Python 3.9+ with `pip` and `venv`.
- A .NET runtime compatible with the bundled WSS assemblies, with the same architecture as Python. `pythonnet` bridges Python to that runtime; installing the Python package alone does not install .NET.
- Keep the complete `Cs_Libraries/` payload beside this source checkout, including platform backend/native subdirectories. Use an editable/source installation so those assets remain available.

On macOS/Linux, select CoreCLR before starting Python: `export PYTHONNET_RUNTIME=coreclr`. In PowerShell, use `$env:PYTHONNET_RUNTIME = 'coreclr'` when using CoreCLR. Use a runtime compatible with your release payload; a .NET SDK is only needed when building .NET code.

## Install in your application

From the root of an existing Git application repository:

```bash
git submodule add https://github.com/cwru-non-academic/Python_WSS_Integration_Lib.git external/wss-py-wrapper
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e external/wss-py-wrapper
```

On Windows, create the environment with `py -m venv .venv` and activate it with `.\.venv\Scripts\Activate.ps1`, then run the same `python -m pip` command.

For an application that already includes the submodule, use `git submodule update --init --recursive` instead of `git submodule add`. Commit the application's submodule pin so collaborators get the same wrapper and DLL payload.

To work directly in this library, clone [this repository](https://github.com/cwru-non-academic/Python_WSS_Integration_Lib), create/activate the same environment, and run `python -m pip install -e .` from its root.

## First run without hardware

Save this as `smoke_test.py` in your application root, beside `external/`, and run `python smoke_test.py` from that directory. It copies the example configuration into an app-owned directory and explicitly selects simulated transport.

```python
from pathlib import Path
import shutil
import time

from wss_py_wrapper import StimulationController, WssConfig

root = Path(__file__).resolve().parent
library = root / "external" / "wss-py-wrapper"
config_dir = root / "wss-config"
if not config_dir.exists():
    shutil.copytree(library / "Config", config_dir)

controller = StimulationController(WssConfig(
    config_path=config_dir,
    log_path=root / "wss-smoke.log",
    cs_lib_dir=library / "Cs_Libraries",
    test_mode=True,
))
try:
    controller.Initialize()
    deadline = time.monotonic() + 10
    while not controller.Started() and time.monotonic() < deadline:
        time.sleep(0.01)
    if not controller.Started():
        raise TimeoutError("WSS did not reach its running state; inspect wss-smoke.log")
    print("WSS running (simulated transport)")
finally:
    controller.Shutdown()
```

The controller advances the stack on its background tick thread. Keep it alive while using it, wait for `Started()` to confirm the normal initialized stack is running, and always call `Shutdown()` in cleanup. `Ready()` reports a transient setup state; the default setup starts stimulation and advances to the started/streaming states covered by `Started()`. In this example those states use simulated transport only. The application owns config/log paths; avoid relying on the current working directory or `WssConfig.default()` when the library is a submodule.

## Connect your application

Keep the same lifecycle and replace simulation with your selected transport. For serial, use `test_mode=False` and an explicit `serial_port` such as `COM5` or `/dev/ttyACM0`. For BLE, set `transport="ble"` and an exact `ble_device_name` or `ble_device_id`; `ble_auto=True` explicitly permits automatic selection. BLE uses the packaged Windows, Linux, or macOS backend. Do not combine BLE selection with serial/test options.

Use the shared [configuration reference](https://cwru-non-academic.github.io/WSS_Documentation/apiDocs/conceptual/config-files-reference.html) to prepare your hardware configuration before opening a physical transport. API calls such as `StartStimulation()`, `StimWithMode("ch2", magnitude)`, and `StopStimulation()` belong to the application workflow once setup has completed.

## Development reference

Runtime package metadata is in [pyproject.toml](pyproject.toml); [src/wss_py_wrapper](src/wss_py_wrapper) contains the API. Build Sphinx reference docs with `python -m pip install -e ".[docs]"` followed by `sphinx-build -b html docs docs/_build/html`.
