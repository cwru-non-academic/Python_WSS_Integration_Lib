# wss-py-wrapper

Python wrapper around the HFI_WSS_Interface .NET library using `pythonnet`.

This repository is the reusable wrapper/library repo. It is intended to be consumed directly as a Python package or included from another repository as a git submodule.

This README contains repository setup, usage and maintenance documentation. The shared [WSS API reference](https://cwru-non-academic.github.io/WSS_Documentation/) covers the API and related implementations.

## Repository Layout

- `src/wss_py_wrapper/`: Python package source
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

Build package:

```bash
python -m pip install -U build
python -m build
```

## Conformance and automatic dependency promotion

See [Maintainer reference](#maintainer-reference) below for canonical tests, CI checks, artifact provenance, dev promotion and human merge gates.

## Explicit BLE transport

Serial remains the default. To select a packaged BLE backend, construct
`WssConfig(..., transport="ble", ble_device_name="WSS")`, use
`ble_device_id="..."`, or explicitly set `ble_auto=True`. Then use the existing
controller initialization/lifecycle. Do not combine BLE selection with Serial,
Test or Conformance options. The exact legacy distribution does not provide a
macOS BLE backend; the new declared distribution requires both its managed backend
and universal native bridge. See [macOS BLE receiver contract](#macos-ble-receiver-contract) below.

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
physical stimulation. The shared profile-specific canonical suites use Core's
emulator and unchanged validators. Real device, permissions and radio behavior require
separate manual validation on the target OS.

`Config/stimConfig.json` now exposes existing Core receiver settings:
`broadcastTarget: "0x8F"` and `wssTargets: ["0x81", "0x82", "0x83"]`. These
are receiver addresses, not a configurable host sender byte. Existing user files
are not replaced; legacy files use the historical defaults, and custom addresses
such as Wss1 `"0x80"` remain supported. Keep hardware-specific firmware and
calibration settings. `LoadCoreConfigFile()` uses the host reset path to rebuild the address map; wait for `Started()` before sending new stimulation.

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
hooks. The receiver declaration and workflow must be available on both branches when a
staged Core producer freezes its plan. Ordinary PR CI alone does not prove live
fan-out; that requires a real staged resume.

## Maintainer reference

<details>
<summary>Contributing, CI, promotion contracts and provenance</summary>

The exact Git commits, content hashes and artifact IDs below identify reviewed
test sources, executable validators or historical evidence. Operational pins in
the workflows, scripts and JSON records are authoritative. Historical evidence
is not current release approval.

## Contributor conventions

The package is library-focused; consuming applications own CLI and app orchestration.
Preserve public names (including PascalCase names that mirror C#) and export new
stable public APIs through `src/wss_py_wrapper/__init__.py` and `__all__`.

Use four-space indentation, PEP 8, grouped standard-library/third-party/local
imports, `from __future__ import annotations` in new modules, `pathlib.Path`,
and return annotations for public methods. Keep optional pythonnet/.NET imports
inside runtime-loading functions. Keep broad exception handling at defensive
interop/probing and background-thread boundaries; otherwise raise specific
`RuntimeError`, `ValueError`, or `FileNotFoundError` exceptions as appropriate.

Keep start/stop/shutdown idempotent and thread-safe, guard shared state with the
controller's `_gate`, and avoid slow interop calls while holding a lock where
possible. Shutdown must stop the tick thread and dispose managed objects.
Route C# logging through `FileLogSink` and `install_csharp_log_sink` defensively.
Keep runtime probing in the loader; respect an initialized CLR or explicit
`PYTHONNET_RUNTIME`, and load managed entry assemblies before the Core facade.

Run the receiver unit checks from the repository root:

```bash
python -m unittest discover -s tests -v
```

Promotion contract checks use PowerShell 7 and Node.js:

```powershell
./.github/scripts/tests/Test-PythonFanout.ps1
./.github/scripts/tests/Test-MacOSReceiver.ps1
./.github/scripts/tests/Test-CandidateProvenance.ps1
./.github/scripts/tests/Test-ReleaseReceiptContract.ps1
node --test .github/scripts/tests/ReceiptGuards.test.mjs
```

Build the package after packaging changes and run the relevant hosted conformance
and platform checks for interop/runtime changes. The optional formatter/type-check
commands above are not configured repository acceptance checks. Do not commit
virtual environments, Python caches, logs, package build outputs or personal
editor/OS files; existing ignore rules cover them.

## Python repository conformance automation

The versioned CLI/ROS fan-out extension is specified in
[Python application promotion contract](#python-application-promotion-contract). New wrapper promotions
require `wss-python-promotion/v2` with independent wrapper, CLI and ROS candidate
preflight proofs. The existing CLI workflow inputs and evidence remain compatible;
legacy v1 approvals cannot authorize a new wrapper or ROS promotion. Both apps
independently validate the actual human-merged wrapper, run a fresh preflight and
open their own gitlink-only dev PR. The dispatcher uses separate matrix jobs with
`fail-fast: false`, so failure in one app does not cancel the other.

The integration fan-out tools and ROS workflow baseline must be deployed through
reviewed dev/main PRs before that chain is used. The existing App installation must allow
ROS repository access and the same delayed scoped permissions used for CLI.
No App grants, credentials or security settings are changed here. A missing ROS
baseline, failed ROS evidence or missing App capability blocks changed-payload
promotion; it is never relabeled as CLI acceptance. Normal CI also runs the
`Promotion safety contracts` check for schema, marker, scope and fan-out failures.

### Production path and unchanged cases

Ordinary validation selects fixture identity and case inventories from the
[profile contract](.github/scripts/PythonProfiles/Contract.ps1) after verifying the
installed payload profile. Candidate fixture inputs remain declared in
[`.github/python-ci.json`](.github/python-ci.json).
The central [verification pin reference](https://github.com/cwru-non-academic/WSS_Documentation/blob/dev/apiDocs/conceptual/verification-pin-reference.md)
explains fixture and receiver pins as a dated inspection snapshot, rather than a
list of currently deployed values. The reviewed source contracts remain authoritative.
The canonical fixture is reused directly for the verified payload profile. Only
its controller factory and type alias change; shared scenarios/values, finite
waits, evaluators and assertions remain unchanged. The reviewed legacy profile
retains ten cases and eighteen assertion expressions. The modern layered profile
requires both sixteen-case single-device and sixteen-case multi-device suites,
with twenty assertion expressions per stage. See the
[profile contract](.github/scripts/PythonProfiles/README.md) for fixture identities.
Case names retain the canonical CSharp wording for cross-repository comparison.

`conformance/PythonConformanceAdapter.cs` embeds CPython 3.12 with pythonnet 3.0.5
in a disposable .NET 9.0.316 NUnit host. Every tested command enters the actual
`wss_py_wrapper.StimulationController`, its real tick thread and
Core -> StimParamsLayer -> ModelParamsLayer stack over `EmulatedWssTransport`.
The adapter translates calls and managed-object identity only; it implements no
stimulation behavior or expected values. Python's `GetConformance` exposes Core's
actual evaluator. CLI mode constructs that controller through the application's
production `wss_cli.main.create_controller`, also used by its normal entry point.

The loader respects an already initialized CLR or explicit PYTHONNET_RUNTIME,
loads managed entry DLLs rather than recursively loading native/backend binaries,
and selects the packaged platform Ports 8 runtime under CoreCLR. Legacy .NET
namespace/constructor and netfx paths remain available for older payloads.

### Checks and evidence

| Role | Workflow | Acceptance |
| --- | --- | --- |
| Integration committed | WSS integration compatibility | Integration behavioral tests |
| Integration candidate | WSS downloaded-artifact preflight | Preflight behavioral tests |
| CLI committed | CLI CI | CLI general conformance |
| CLI candidate | WSS CLI preflight | CLI general conformance |

Workflow files match the C# naming: `wss-compatibility.yml`, `wss-preflight.yml`,
`cli-ci.yml`, `promote-wss.yml`, `dispatch-cli-promotion.yml`, and
`promote-integration.yml`. Promotion names are **Promote WSS into Integration**,
**Dispatch CLI Integration promotion**, and **Promote Integration submodule**.
Dependency PR titles match C#: **Promote universal WSS run {run_id}** for the
integration and **Promote universal WSS run {run_id} / Integration {short_sha}**
for the CLI gitlink update.

`Invoke-DotNetConformance.ps1` verifies clean exact source SHAs, the canonical
fixture hash, the complete original universal inventory and every file hash before
and after execution. Candidate mode stages a fresh verified payload and never
falls back to committed DLLs. NUnit XML must contain the exact expected cases for
each required profile stage, all executed/passed with zero skips/failures. Modern
candidate evidence requires paired single-device and multi-device results.
Evidence records Python execution, runtime versions, source SHAs,
producer/artifact/archive tuple, payload digest, profile-specific unchanged
assertion expressions and XML/log hashes.

Successful committed runs retain `dotnet-conformance-evidence` with schema
`wss-python-profile-evidence/v1`; candidate runs retain `python-preflight-evidence`
with schema `wss-python-evidence/v1`. Both record `execution: pythonnet` and require
`python_executed: true`. The hosted process
is .NET embedding Python; this is actual Python execution, not .NET-only evidence.
Ordinary CI uses public read-only checkouts without App secrets.

Local validation, using a new output directory outside source checkouts:

```powershell
python -m pip install pythonnet==3.0.5
./.github/scripts/Invoke-DotNetConformance.ps1 `
  -WrapperRoot <clean-wrapper> -WrapperSha <exact-sha> `
  -FixtureRoot <pinned-csharp-fixture> -ConfigPath .github/python-ci.json `
  -OutputRoot <new-results-directory> -PythonExe python
```

Use `-Role cli -CliRoot <clean-cli> -CliSha <exact-sha>` for CLI validation.
SDK 9.0.316 and Windows CPython 3.12 are required by the canonical behavioral host.

### Automatic promotion and deployment

Routine promotions target **dev** and require human merges. Core's separate
`propagate-python.yml` completion handler verifies a genuine successful
`artifacts.yml` dev push, all eleven required producer jobs, dev ancestry, the
exact unexpired artifact ID, archive checksum and downstream default-branch
readiness before minting an existing App dispatch token. Existing C# and Unity
handoffs remain separate.

A changed payload requires independent immutable-source wrapper, CLI and ROS
candidate preflights. Only validated matching v2 evidence allows a dependency-only
integration PR. After its human merge, the dispatcher verifies the actual merged
payload bytes, approval marker and final-head normal PR CI. Each application
independently revalidates that proof, preflights the actual merged wrapper and its
own current source, then opens its own gitlink-only dev PR. Role-specific approval
markers bind those exact sources and runs. No automatic merges/releases occur.

Identical payloads preserve committed provenance and produce a verified no-op.
An existing matching PR is reused; closed/merged PRs, orphan branches, stale source
or conflicting evidence stop without force push or blind redispatch.

Reviewed integration, CLI and ROS workflow baselines must be available on default
**main** as well as dev before a Core handoff can use them. GitHub registers dispatch/completion workflows
from the default branch. These are human merge gates, not an observed propagation
success. Existing `WSS_GITHUB_APP_ID` / `WSS_GITHUB_APP_PRIVATE_KEY` configuration
and App access to the integration, CLI and ROS repositories are required but are not created or
changed here. A missing capability stops that hop with an actionable failure.

The historical initial payload and its exact producer/artifact/archive identities
are recorded in [`.github/python-bootstrap.json`](.github/python-bootstrap.json).
It preserves its C# reference approval explicitly as C#
evidence; new Python CI establishes Python acceptance. Copying that baseline or
observing an unchanged-payload no-op does not establish full automatic propagation.

### Manual verification and coverage limits

These suites establish production Python API mapping/lifecycle and Core emulator
protocol/state behavior. CLI evidence covers production controller construction,
not terminal command parsing, interactive input/output, or every CLI command.
The suite does not prove physical Serial/BLE behavior, native backend activation,
GUI behavior, hardware safety, or compatibility across all Python/.NET versions.

### Separate behavior and platform checks

Ordinary CI runs the canonical suites required by the verified installed payload
profile in `Integration behavioral tests` or `CLI general conformance` directly,
with no aggregate acceptance alias. Modern products require paired single-device
and multi-device suites; reviewed legacy products retain their ten-case baseline.
The embedding host remains Windows CPython 3.12;
this behavioral result makes no claim about other operating systems.

Independent jobs named `Integration compatibility (Windows)`, `(Ubuntu)`,
`(macOS)` and `CLI platform compatibility (Windows)`, `(Ubuntu)`, `(macOS)` run
on their respective OS runners. Each builds and installs wheels in an isolated
consumer directory, verifies the complete payload inventory and hashes, checks
actual production Python Ports runtime selection/construction, and runs the
pinned C# SerialRuntimeSelectionTests/BleBackendLoadingTests against that same
payload. CLI jobs also run installed module help/argument parsing away from the
source checkout. These are platform/package checks, not repetitions of the
emulator scenarios. Python wheels contain source; the verified universal runtime
payload is staged beside the installed package, matching the documented layout.

macOS requires both native Intel (x86_64) and ARM64 runner evidence. The exact
legacy payload explicitly reports unsupported BLE; a payload declaring the macOS
BLE inventory must pass managed activation and native ABI checks, and its shared
C# BLE test must pass without a skip. See
[macOS BLE receiver contract](#macos-ble-receiver-contract) for the two exact contracts and
the canonical producer/receiver preparation boundary.
No check opens a physical serial port or connects to a BLE device. The existing
candidate preflights, versioned producer provenance, CLI/ROS fan-out and App
permissions are unchanged. PRs to both main and dev, and pushes to both branches,
run ordinary CI. CLI platform tools are pinned to an immutable reviewed source;
the application still consumes its own committed wrapper gitlink. Candidate
preflights also run the three platform jobs, and new macOS payload proof requires
their source/hash-bound native smoke evidence.

The first Unix matrix run exposed pythonnet 3.0.5 treating suffixed absolute DLL
paths as assembly names. The production loader now gives its path probe the
absolute path without the suffix; pythonnet appends `.dll` and loads that same
file before attempting assembly-name lookup. The installed-package checks retain
this regression coverage on Windows, Ubuntu and macOS.

## macOS BLE receiver contract

The receiver accepts exactly two universal distributions: the original 25 files,
or those files plus `backends/macos/WSS.Transport.BLE.MacOS.dll` and
`backends/macos/libwss_macos_ble.dylib`. New projections declare
`universal_contract: macos-ble-v1`; legacy records without the field remain valid
only for the exact original inventory. Partial pairs, extra files, missing or
changed declared files, and inventory/proof mismatches fail. The native dylib is
copied recursively with its original hash. Producer manifest lookup at the exact
Core SHA prevents a new producer from being approved with a legacy projection.

Python keeps Serial as its default. `WssConfig(transport="ble",
ble_device_name="...")`, `ble_device_id` or explicit `ble_auto=True` selects the
packaged BLE facade. BLE cannot be combined with Serial, Test or Conformance
selection. Backend assemblies are loaded from the selected payload before the
facade constructs its shared factory: Python's application base is its interpreter,
not the payload directory. Construction does not initialize Bluetooth or a device.
The normal application initializes/connects only after the user selects BLE and
starts it; ordinary CI never does so.

The existing four ordinary check names are unchanged. For a declared macOS
distribution, platform checks require both x86_64/arm64 Mach-O slices and the exact
managed assembly identity/version/netstandard2.0 framework. On the macOS receiver
host they construct the production facade/backend, verify all five C exports,
check ABI `0x00010000`, create/release an inert native context and call the managed
`MacBleBackend.VerifyNativeAbi` bootstrap. No initialize/discovery/connect/write
command is submitted. macOS legacy payloads explicitly report unsupported BLE;
declared new payloads cannot take that path. The pinned C# platform fixture must
also execute its macOS BLE case successfully; a skipped old fixture fails the new
contract. Physical-device support is a separate validation boundary.

Candidate preflights now run actual package/platform checks on Windows, Ubuntu and
macOS alongside the required modern single-device and multi-device shared Core
conformance suites.
For a new producer, proof requires all three platform jobs and hash/source/run-bound
native smoke reports. Canonical producer proof additionally requires:

- `Build macOS universal BLE bridge`
- `BLE consumer (macOS arm64)`
- `BLE consumer (macOS x86_64)`

The existing successful `artifacts.yml` **push to dev**, dev ancestry, exact
run/artifact/archive/checksum and whole-run-success requirements remain intact.
An otherwise green Core PR run is rejected. Historical diagnostic artifacts remain
identified by their original workflow evidence. Integrity-checked local receiver verification is
not candidate-preflight approval and cannot authorize automatic publication.

### Producer and receiver prerequisites

Promotion requires the reviewed macOS-aware C# fixture pin and macOS-aware
receiver tooling on the intended branches. A merge into Core main
does not create canonical dev-push proof by itself: the reviewed feature must be
included in dev through the approved branch workflow, then the genuine dev-push
artifact must pass its own complete producer run. Existing preflight/promotion entry points require that canonical dev-push
immutable tuple; the historical PR tuple above is local verification evidence.

The current v2 Python wrapper promotion still requires independent wrapper, CLI
and ROS proofs and later dispatches both applications. That requirement has not
been relaxed to manufacture a CLI-only success. ROS receiver readiness and any
limited traversal must be coordinated before dispatch. These requirements do not grant GitHub App permissions or change credentials
or rulesets.

## Python application promotion contract

CLI and ROS retain independent workflow inputs and canonical evidence. ROS
acceptance requires real hosted ROS evidence that passes the validators below.

### Sources, workflows and roles

| Role | Repository | Integration gitlink | Normal acceptance |
| --- | --- | --- | --- |
| wrapper | Python_WSS_Integration_Lib | n/a | Integration behavioral tests |
| cli | CLI_Python_WSS_Application | external/wss-py-wrapper | CLI general conformance |
| ros | ROS_Python_WSS_Application | HFI_WSS_Python_Interface | ROS compatibility |

The ROS normal workflow file is `ros-ci.yml`. All repositories belong to
`cwru-non-academic`. Routine promotion targets `dev`;
dispatch workflows must also be registered on default `main` before deployment.
ROS supplies `.github/python-ci.json` matching the established pinned fixture and
runtime contract. The existing library `_python-validation.yml` remains the
wrapper/CLI host; ROS owns its real ROS-compatible runner and canonical harness.

`wss-preflight.yml` retains `candidate_json`, `wrapper_sha`, `cli_sha`,
`correlation_id` for wrapper/CLI. ROS accepts `candidate_json`, `wrapper_sha`,
`ros_sha`, `correlation_id`. Each workflow's run-name is exactly
`WSS preflight {candidate.run_id} / {correlation_id}`. Correlation is
`wss-{run_id}-{artifact_id}-{wrapper_sha}-{application_sha}`. Existing correlated
runs are reused; ambiguous/failed requests are not blindly redispatched.

Every application accepts `promote-integration.yml` with `wrapper_sha`,
`wrapper_pr`, `approval_json`. Run-name is exactly
`Promote Integration {wrapper_sha} / wss-{run_id}-{artifact_id}`. That workflow
uses trusted integration tools from `dev` and calls
`Prepare-PythonPromotion.ps1 -Role cli|ros`, followed by the existing publisher.
Its approval/evidence read token must cover WSSCore, Python_WSS_Integration_Lib,
CLI_Python_WSS_Application and ROS_Python_WSS_Application with contents, Actions
and pull-request read permission. Dispatch and publication tokens remain limited
to the individual target application. This requests existing App capabilities;
it does not create installation grants or change security settings.

### Versioned approval and evidence

New wrapper promotion requires `wss-python-promotion/v2`. The example below uses
placeholders for exact identities. Actual approvals use the current
`fixture_commit` and `fixture_sha256` from
[`.github/python-ci.json`](.github/python-ci.json), as the publisher does. Copying
a historical fixture commit into a current approval can fail validation.

```json
{
  "schema": "wss-python-promotion/v2",
  "candidate": {"repository": "cwru-non-academic/WSSCore", "commit": "FULL_SHA", "run_id": "ID", "artifact_id": "ID", "archive": "WSS-Universal-ci.zip", "sha256": "SHA256"},
  "wrapper": {"source_sha": "FULL_SHA", "preflight_run_id": "ID"},
  "cli": {"source_sha": "FULL_SHA", "preflight_run_id": "ID"},
  "ros": {"source_sha": "FULL_SHA", "preflight_run_id": "ID"},
  "fixture": {"commit": "FIXTURE_COMMIT_FROM_CONFIG", "sha256": "FIXTURE_SHA256_FROM_CONFIG"},
  "projection_sha256": "SHA256"
}
```

The canonical PR marker is `<!-- wss-python-approval:v2 BASE64 -->`, where
BASE64 is UTF-8 of the normalized, ordered compact approval JSON. Legacy v1
approvals remain readable for already-issued CLI requests; they cannot authorize
a new wrapper promotion or ROS promotion.

All three candidate acceptance jobs must pass before a new wrapper dependency PR.
Wrapper/CLI evidence remains `wss-python-evidence/v1`, artifact
`python-preflight-evidence`, with the exact inventory declared by
[`Get-PythonEvidenceFiles`](.github/scripts/PythonPromotion.ps1): `evidence.json`,
`results.xml`, `dotnet.log` and `projection.json` at the root and again under
`multi/` for eight canonical files. ROS uses that same artifact/envelope, with role
`ros`, `wrapper_sha`, `ros_sha`, and its exact own `run_sha`/repository/run ID.
Wrapper/CLI bind their wrapper/CLI source pair independently; ROS binds its
wrapper/ROS pair. The v2 approval binds all three sources and the same candidate,
fixture and payload digest. CLI does not depend on ROS source at runtime.

Evidence must record actual pythonnet execution (`execution: pythonnet`,
`python_executed: true`), SDK 9.0.316, net9.0, NUnit 3.14.0, Python 3.12,
pythonnet 3.0.5, the exact sixteen canonical cases discovered/executed/passed in
each of the single-device and multi-device stages, zero failures/skips, twenty
unchanged assertion expressions per stage, fixture identity, candidate identity,
projection digest and XML/log SHA256 values. Both stages must bind the same
source/candidate identities. ROS must generate real canonical NUnit results
through its production path. No stubbed ROS result,
CLI-only proof or generated green summary substitutes for that evidence.

ROS retains its two independently executed ROS suites and runs both modern
canonical stages in the Windows job. Candidate acceptance requires all three
successful, non-skipped jobs by their exact names:

- `ROS compatibility`
- `ROS model and contract fixtures (Windows development host)`
- `ROS colcon and installed DDS fixture (Humble development baseline)`

The ROS artifact has exactly **eleven** files: the eight canonical files above,
plus `ros-model.json`, `ros-native-symlink.json`, `ros-native-copy.json`. The
envelope adds `ros_model_sha256`, `ros_native_symlink_sha256`,
`ros_native_copy_sha256` and `native_ros_distribution: humble`. Its Python/SDK
fields describe the Windows canonical host, not the distinct native ROS host.

`ros-model.json` preserves `wss-ros-emulator/v1`: at least five real Core model
tests, zero failures/skips, and all fifteen original mode/amplitude/firmware/device
observations, conformant initialization and zero protocol errors. Expected drive
assertions stay in the ROS tests, including explicit characterization of the
pre-existing capacity issue; promotion code does not invent substitute values.
The two `wss-ros-native/v1` reports must pass with all nine DDS channels in their
respective copied/symlink installed layouts. These remain clearly distinguished:
actual Core with ROS doubles versus actual rclpy/DDS with a managed recording
double. The canonical-stage assertions supplement both ROS suites and are not relabeled
as proof of DDS or StimWithMode coverage. Missing any report/hash/job fails closed.

`projection.json` uses the existing `wss-python-projection/v1` complete universal
inventory and file hashes. The released payload is never rebuilt or overlaid.

### Independent application promotion

After a human merges an accepted wrapper dependency PR into `dev`, independent
CLI and ROS dispatcher jobs validate the original proof, actual merged wrapper
bytes and final-head normal PR CI. Each app then preflights the actual merged
wrapper and its own current source again, and opens its own gitlink-only `dev` PR.
An application's failure cannot cancel its sibling. Publication checks exact
target/source/tree, existing PR/branch markers and allowlisted paths before push.
There are no automatic merges, security changes or fabricated Core events.

The original approval and a role-specific merged-wrapper preflight marker are
retained in each app PR. Titles remain
`Promote universal WSS run {run_id} / Integration {short_wrapper_sha}`.
An identical payload or gitlink remains a verified no-op with no artificial PR.

## Dev beta acceptance receiver

Implements the dev-only acceptance interface defined by the reviewed WSSCore
verifier selected in [the receipt workflow](.github/workflows/release-receipt.yml).
Main/stable publication remains disabled. All nine downstream targets, including
MATLAB, are required by the shared contract. This tooling never creates dependency PRs, merges them, or releases.

The receipt workflow and validators must be deployed through reviewed PRs to main
and dev before frozen-plan production. Closed-event fan-out checks out main, so
the reviewed merged-wrapper CI-association validation must also be available
there; a dev-only fix does not repair that automatic control path.
Do not replace the caller's merge with a different dependency or replay an old
closed-event run against its old source.

The reconciliation workflow accepts only `producer_run_id` and `plan_id`. It
downloads the unique frozen producer plan and exact ZIP, validates the reviewed
policy/digests, checks all producer gates, and requires exact current dev state.
Receipt code, normal CI and scripts must have the frozen Git IDs. A preparation
merge or no-op cannot become a `merged-pr` acceptance receipt.

The emitter is read-only. It invokes the existing v2 approval, source-scope,
archive checksum, strict 25/27-file projection, paired modern canonical-stage,
platform, and ROS native validators. Applications additionally prove their actual
human-merged parent and fresh merged-wrapper preflight. Every original proof
source must match its frozen target snapshot. Latest actual-merge push/dispatch
CI must succeed; synthetic PR checkout CI cannot replace it. Core independently
rechecks the receipt, current branches, Git IDs, CI, dependency pins and emitter.

Successful preflights additionally upload `wss-candidate-provenance` with exactly
one six-string-field `candidate.json`. This is bound to their existing canonical
and projection evidence, and is uploaded only after all existing suites pass.
Rich Python/native/platform artifacts and all v2 validation remain intact.

An old preflight without that additional artifact is not release acceptance.
A fresh producer plan and proofs are required after tooling deployment; neither
the earlier macOS candidate nor the later policy-only candidate can manufacture
a missing frozen plan, normalized proof, no-op equivalence, or all-clear receipt.

Unit checks cover metadata binding, source/marker ambiguity, changed/no-op state,
exact required checks, non-human or wrong-source merges, latest-failed normal CI,
and disallowed transport writes. End-to-end acceptance requires a real frozen
plan and reviewed dependency merges after deployment; unit metadata is not proof.

</details>


## Coordinated configuration reload

`LoadParamsJson()` rereads all three files (`stimConfig.json`, `stimParams.json`,
`modelConfig.json`) from the original startup configuration directory, including
after a profile override. Startup paths are anchored once, so changing the
working directory does not move these defaults.

- `LoadParamsJson(directory)` selects all three standard filenames in that directory.
- `LoadParamsJson(parameterFile)` selects that calibration file and the startup-default
  Core and model files. It does **not** select sibling Core/model files.
- `LoadCoreConfigFile()` and `resetRadio()` reread the active Core file and keep
  currently applied calibration/model values and paths.

Every bundle is validated before changing the working connection. Any Core
configuration change uses the host reset path: stop ticking, dispose the old
stack (Core zeros output and disconnects), build the validated snapshot, then
resume initialization/ticking. Unchanged Core applies calibration/model updates
without reconnecting. A reset does not replay previous stimulation values.
Wait for `Started()` before sending new stimulation commands.

Invalid JSON leaves the active stack unchanged. Cleanup/construction failure
is exposed through `LastReloadError` and the host stays unavailable rather than
publishing an unverified replacement. `RetryReload()` retries the retained
snapshot without rereading files. `Shutdown()` cancels a pending reload.

`UpdateChannelParams` writes amplitude to `stim.ch.<channel>.defaultPA`, the key
consumed by calibrated stimulation, and saves it using the existing parameter API.

The reload regressions use the packaged Core emulator and verify model and
calibration input reaches emitted stimulation, profile/file/default paths,
retired-stack quiescence, and invalid-bundle behavior. They do not validate
physical hardware.
