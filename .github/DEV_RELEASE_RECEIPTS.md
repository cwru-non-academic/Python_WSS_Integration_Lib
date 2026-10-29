# Dev beta acceptance receiver

Implements the dev-only acceptance interface in WSSCore PR #18 at immutable
`de631fe4f1b80b5b4e2c6691f444625ef1730499`. Main/stable is disabled and MATLAB
is excluded. This tooling never creates dependency PRs, merges them, or releases.

Deploy the receipt workflow and validator code through reviewed PRs to main and
dev before Core enables frozen-plan production. Default/main also needs the
reviewed merged-wrapper CI-association fix: the closed-event fan-out currently
checks out main, so a dev-only fix does not repair that automatic control path.
Do not replace the caller's merge with a different dependency or replay an old
closed-event run against its old source.

The reconciliation workflow accepts only `producer_run_id` and `plan_id`. It
downloads the unique frozen producer plan and exact ZIP, validates the reviewed
policy/digests, checks all producer gates, and requires exact current dev state.
Receipt code, normal CI and scripts must have the frozen Git IDs. A preparation
merge or no-op cannot become a `merged-pr` acceptance receipt.

The emitter is read-only. It invokes the existing v2 approval, source-scope,
archive checksum, strict 25/27-file projection, canonical 10-case/18-assertion,
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
