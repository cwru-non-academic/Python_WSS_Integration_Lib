# Inactive Python selected-test consumer integration

Nothing in this directory is an active GitHub Actions workflow. No lock, literal
workflow pin, live policy, product configuration, gitlink, or payload was changed.
Activation requires reviewed current-contract Core tooling, matching immutable
consumer pins, bootstrap trust and isolated hosted executor integration.
Shared source adoption alone does not complete selected execution.

## Legacy online bridge behavior

The online inspect/evidence and WithContext behavior below remains supported for
API compatibility. The adjacent fragment is a legacy integration recipe, not a
deployable offline job graph. Readiness checks alone do not make it deployable:
activation requires a separately reviewed current-contract flow with trusted
authentication and a separate credential-free hosted executor receiving no
source/plan, App or publishing credentials, including read tokens.

`Invoke-SelectedPythonTestsWithContext.ps1` accepts CoreRoot, ContextPath,
RootsPath, WorkRoot, Mode, optional authenticated ArtifactRoot/CandidatePath,
and PythonExe. It calls the full locked Core `ci-test-selection.mjs inspect`
for `python-wrapper`, executes the fixed capability-appropriate baseline, executes
an additional selected suite with the same mandatory profile, then calls Core `evidence`. The selected tuple
comes only from authenticated inspection. Both executions use identical original
product roots, runtime config, bootstrap-owned canonical fixture and candidate projection inputs.
Each suite executes in an isolated child process with credential variables, SSH
authentication handles and GitHub command-file handles removed. Parent credentials
and environment are never mutated. Child environment filtering is a local
orchestration control, not a substitute for the separate credential-free hosted
executor required before activation. A failed inspect or suite cannot emit evidence.

The generic evidence is the sole `evidence.json` in
`wss-selected-tests-python-wrapper-a<attempt>`. Rich baseline and selected runtime
proof remains separate. This artifact adds a requirement; it never substitutes
for conformance, platform/native, producer, approval, receipt, or release gates.

## Fragment integration prerequisites

`python-selection.fragment.yml` is for the wrapper target only. It expects the
existing source prerequisite outputs wrapper, cli, fixture, sdk and inputs role,
mode, candidate_json. Before activation, explicitly add validated `channel`
(dev/main) and `wss_github_app_id` inputs to the enclosing reviewed workflow.
Keep its literal immutable caller pins and existing source/approval validation.

Map `mandatory-python-gates` to a real success-only barrier covering EVERY
unchanged ordinary/candidate/platform/native gate in that registered workflow.
This fragment intentionally does not invent a pass-only implementation of the
barrier. Preserve skipped/failed gate semantics. The final selected artifact
must never publish if any required existing gate failed or did not run.

The selection prerequisite checks out the full immutable Core tree, verifies its
checked-in source lock, and passes actual runner identity and explicit channel.
The reviewed resolver job declares no environment and maps the fixed
WSS_LOCAL_TEST_VARIABLES_SCHEMA=wss-effective-test-variables/v1 contract plus
WSS_USE_PIN_TESTS, WSS_PIN_TEST_REPOSITORY and WSS_PIN_TEST_COMMIT from effective
org/repository vars through env. These three settings are user-configurable;
repository values override organization values. No Variables-read token or new
App grant is required. Follow the reviewed Core
tools/ci/LOCAL_TEST_VARIABLE_SNAPSHOTS.md; source/plan access retains scoped read
authority, and campaign snapshot dispatch uses existing Actions/Contents capabilities.

The prerequisite calls `select` once to prepare a durable envelope. It uploads
only when created=true, using the helper's immutable artifact_name, then calls
`load` to independently authenticate the durable artifact before emitting any
selection coordinates. A retry recovers the same envelope without re-reading
settings or branch heads. Missing/corrupt recovery evidence fails closed.

Dependent jobs call `load` with the same actual candidate/mode to materialize raw
context, verify its ID against the immutable prerequisite output, and retain that
prerequisite ID in WSS_TEST_SELECTION_ID for inspect/evidence. They never use a
self-reported downloaded ID as authority. Preserve actual GITHUB_WORKFLOW_REF,
GITHUB_WORKFLOW_SHA, GITHUB_REF, and other runner identity variables unchanged.

Fresh bootstrap, Core, actual product, selected test and fixture checkouts are
separate and have persist-credentials:false. Selected gitlinks remain uninitialized.
The Python wrapper has no product gitlinks. A candidate CLI checkout is separately
declared and its historical wrapper gitlink remains uninitialized; never insert
candidate wrapper bytes into that historical pin. If future product gitlinks are
initialized, declare every actual child path/repository/indexed SHA in products;
Core authenticates them independently. Never change product inputs for new tests.

The profiled runner verifies the exact payload projection first, then reads PE
metadata without executing the product assembly. The approved legacy producer
runs all ten original canonical cases; complete modern capability runs sixteen
single plus sixteen multi cases. Missing/partial APIs fail closed. Only a Core-
authenticated selection-enabled campaign requires modern capability; ordinary
run-level contexts and legacy producer policies retain their original coverage.
The selected manifest declares supported profiles but cannot select the product
profile or weaken the bootstrap-owned fixture hashes, assertions or inventories.
External product fixture pins are not changed to satisfy selected tests.

## Local verification and remaining activation blockers

`tests/Test-PythonSelectedContext.ps1` checks authentication/baseline/selected/
evidence ordering, failure suppression, unchanged product/candidate inputs,
source-output isolation, and a real token-free child process. These mocks are
orchestration unit tests, not authenticated campaign acceptance evidence.

Selected execution remains inactive pending the reviewed caller and trust integration.
Before activation: review dual-profile legacy/layered product reconciliation,
land reviewed shared tooling and refreshed literal pins on both required branches,
validate hosted durable recovery, credentials/permissions and
all mandatory gates, then enable the coordinated policy. Do not publish local
synthetic IDs or treat this fragment as a completed release rollout.
