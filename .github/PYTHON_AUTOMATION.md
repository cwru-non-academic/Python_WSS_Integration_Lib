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
