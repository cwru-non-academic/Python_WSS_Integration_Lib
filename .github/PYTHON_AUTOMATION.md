# Python repository conformance automation

The versioned CLI/ROS fan-out extension is specified in
[`PYTHON_FANOUT_CONTRACT.md`](PYTHON_FANOUT_CONTRACT.md). New wrapper promotions
require `wss-python-promotion/v2` with independent wrapper, CLI and ROS candidate
preflight proofs. The existing CLI workflow inputs and evidence remain compatible;
legacy v1 approvals cannot authorize a new wrapper or ROS promotion. Both apps
independently validate the actual human-merged wrapper, run a fresh preflight and
open their own gitlink-only dev PR. The dispatcher uses separate matrix jobs with
`fail-fast: false`, so failure in one app does not cancel the other.

Deploy the integration fan-out tools and ROS workflow baseline through reviewed
dev/main PRs before enabling that chain. The existing App installation must allow
ROS repository access and the same delayed scoped permissions used for CLI.
No App grants, credentials or security settings are changed here. A missing ROS
baseline, failed ROS evidence or missing App capability blocks changed-payload
promotion; it is never relabeled as CLI acceptance. Normal CI also runs the
`Promotion safety contracts` check for schema, marker, scope and fan-out failures.

## Production path and unchanged cases

The pinned C# fixture at `CSharp_WSS_Integration_Lib` commit
`7145e2307f997f703748530bf74311ef94455e98`, SHA256
`1cdfb9448a1776011eadc9aef8356362216032013a4f268f50242746c50a0b44`,
is reused directly. Only its controller factory and type alias change. All ten
canonical cases, shared scenarios/values, finite waits, evaluators, Assert.Multiple
blocks and eighteen Assert.That expressions remain unchanged. Case names retain
the canonical CSharp wording so identities can be compared across repositories.

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

## Checks and evidence

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
falls back to committed DLLs. NUnit XML must contain exactly ten expected cases,
all executed/passed with zero skips/failures. Evidence records Python execution,
runtime versions, source SHAs, producer/artifact/archive tuple, payload digest,
eighteen unchanged assertion expressions and XML/log hashes.

Successful committed runs retain `dotnet-conformance-evidence`; candidate runs
retain `python-preflight-evidence`. The schema is `wss-python-evidence/v1`,
execution is `pythonnet`, and `python_executed` must be true. The hosted process
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
SDK 9.0.316 and Windows CPython 3.12 are required by this initial tested host.

## Automatic promotion and deployment

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

Humans must publish the integration and CLI dev baselines to default **main**
before merging the Core handoff. GitHub registers dispatch/completion workflows
from the default branch. These are human merge gates, not an observed propagation
success. Existing `WSS_GITHUB_APP_ID` / `WSS_GITHUB_APP_PRIVATE_KEY` configuration
and App access to the integration, CLI and ROS repositories are required but are not created or
changed here. A missing capability stops that hop with an actionable failure.

The initial payload is the independently downloaded Core run `39092192696`,
artifact `12123267360`, commit `5ec22900587587e9e9465ffa53d04d7d1ce13545`,
archive SHA256 `3bc303096594978fa77e95cd80901a8fb72d26c42a7408c38c8668563b6f1a7e`.
`python-bootstrap.json` preserves its C# reference approval explicitly as C#
evidence; new Python CI establishes Python acceptance. Copying that baseline or
observing an unchanged-payload no-op does not establish full automatic propagation.

## Manual verification and coverage limits

These suites establish production Python API mapping/lifecycle and Core emulator
protocol/state behavior. CLI evidence covers production controller construction,
not terminal command parsing, interactive input/output, or every CLI command.
The suite does not prove physical Serial/BLE behavior, native backend activation,
GUI behavior, hardware safety, or compatibility across all Python/.NET versions.

## Separate behavior and platform checks

Ordinary CI runs the unchanged ten-case/eighteen-assertion canonical corpus in
`Integration behavioral tests` or `CLI general conformance` directly, with no
aggregate acceptance alias. The embedding host remains Windows CPython 3.12;
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

macOS uses an x64 runner. The exact legacy payload explicitly reports unsupported
BLE; a payload declaring the macOS BLE inventory must pass managed activation and
native ABI checks, and its shared C# BLE test must pass without a skip. See
[`MACOS_BLE_RECEIVER.md`](MACOS_BLE_RECEIVER.md) for the two exact contracts and
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
