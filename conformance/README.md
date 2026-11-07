# Independently selected Python conformance tests

The trusted product-side `.github/scripts/Invoke-DotNetConformance.ps1` and
`Invoke-PlatformCompatibility.ps1` accept optional `TestRoot`, `TestSha`,
`TestRepository`, and `TestSelectionId` together. With none supplied they retain
product-checkout tests. `WrapperRoot`/`WrapperSha` and `CliRoot`/`CliSha` always
identify production code; selected tests never select or replace its payload.

Explicit selection requires a clean Git checkout at the complete immutable SHA,
including no ignored or untracked conformance files. The trusted campaign
bootstrap must authenticate the frozen selection against its plan and repository
before invoking these runners. A caller-supplied selection ID is only an evidence
binding, not authentication or release authority.

`test-contract.json` is the versioned test-only contract. It supplies the canonical
fixture repository, commit, hash, and both required case inventories. Runtime,
readiness, channels, candidate identity, and projection validation still come from
the product's `.github/python-ci.json` and trusted validators. Product fields in
the test contract are rejected. Canonical assertions and 16+16 coverage remain
mandatory. Future test-only edits belong under `conformance/`, not workflows,
product CI configuration, or the trusted bootstrap scripts.

Both stages record `test_root`, `test_sha`, `test_repository`, `test_selection_id`,
and `test_contract_sha256`; paired evidence must match every field. Legacy evidence
without these fields remains readable. Remote selection discovery and campaign
snapshot authentication belong to the separate trusted Core bootstrap.

Immutable source validation also rejects assume-unchanged/skip-worktree index
flags, ignored Python bytecode, and ignored files under src. Disabling bytecode
writes alone does not prevent cached code from executing. Use clean detached
product checkouts rather than deleting caches from an active developer checkout.
