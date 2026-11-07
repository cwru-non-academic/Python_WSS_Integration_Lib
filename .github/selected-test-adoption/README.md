# Inactive Python selected-test consumer integration

Nothing in this directory is an active GitHub Actions workflow. No lock, literal
workflow pin, live policy, product configuration, gitlink, or payload was changed.
The current checked-in d965 Core lock deliberately refuses the new bridge until
reviewed immutable Core tooling and coordinated consumer pins are deployed.

## Reviewed execution boundary

`Invoke-SelectedPythonTestsWithContext.ps1` accepts CoreRoot, ContextPath,
RootsPath, WorkRoot, Mode, optional authenticated ArtifactRoot/CandidatePath,
and PythonExe. It calls the full locked Core `ci-test-selection.mjs inspect`
for `python-wrapper`, executes the unchanged default 16+16 baseline, executes
an additional selected 16+16 suite, then calls Core `evidence`. The selected tuple
comes only from authenticated inspection. Both executions use identical original
product roots, runtime config, fixture root and candidate projection inputs.
Each suite executes in a child process without GH_TOKEN, GITHUB_TOKEN, or
WSS_TEST_VARIABLE_READ_TOKEN. Authentication credentials are restored only for
the trusted post-test Core check. A failed inspect or suite cannot emit evidence.

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
It obtains repository-only variable data through WSS_TEST_VARIABLE_READ_TOKEN;
no inherited organization/environment `vars` context selects tests. Check the
App's existing Variables-read grant before activation. Requesting the scoped
short-lived token is not permission to expand its installation grants.

The prerequisite freezes once and uploads create-only context.json. Dependent
jobs use its immutable selection_id output, never an ID extracted from a file.
Until an authenticated durable ordinary-run recovery helper is adopted, the
prerequisite fails before selection on attempts after the first. Failed dependent
jobs can reuse the successful prerequisite and artifact. Do not replace this
restriction with fresh settings/branch resolution or a self-reported artifact ID.

Fresh bootstrap, Core, actual product, selected test and fixture checkouts are
separate and have persist-credentials:false. Selected gitlinks remain uninitialized.
The Python wrapper has no product gitlinks. A candidate CLI checkout is separately
declared and its historical wrapper gitlink remains uninitialized; never insert
candidate wrapper bytes into that historical pin. If future product gitlinks are
initialized, declare every actual child path/repository/indexed SHA in products;
Core authenticates them independently. Never change product inputs for new tests.

Currently the bridge shares one exact canonical fixture root between default and
selected suites. The fragment explicitly rejects different fixture commits rather
than repinning the product. Separate baseline/selected fixture dependency handling
must be reviewed before allowing that additional difference. The trusted mandatory
canonical fixture hash and case inventories remain fixed.

## Local verification and remaining activation blockers

`tests/Test-PythonSelectedContext.ps1` checks authentication/baseline/selected/
evidence ordering, failure suppression, unchanged product/candidate inputs,
source-output isolation, and a real token-free child process. These mocks are
orchestration unit tests, not authenticated campaign acceptance evidence.

Real execution with the current unchanged tooling lock is intentionally blocked.
Before activation: finish dual-profile legacy/layered product reconciliation,
land reviewed shared tooling and refreshed literal pins on both required branches,
adopt durable ordinary-run recovery, validate hosted credentials/permissions and
all mandatory gates, then enable the coordinated policy. Do not publish local
synthetic IDs or treat this fragment as a completed release rollout.
