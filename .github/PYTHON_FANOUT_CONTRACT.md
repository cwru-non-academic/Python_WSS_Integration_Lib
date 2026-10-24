# Python application promotion contract

This contract adds ROS without changing the CLI's existing workflow inputs or
canonical evidence. It does not establish ROS acceptance until real hosted ROS
evidence has passed the validators below.

## Sources, workflows and roles

| Role | Repository | Integration gitlink | Normal acceptance |
| --- | --- | --- | --- |
| wrapper | Python_WSS_Integration_Lib | n/a | Integration behavioral tests |
| cli | CLI_Python_WSS_Application | external/wss-py-wrapper | CLI general conformance |
| ros | ROS_Python_WSS_Application | HFI_WSS_Python_Interface | ROS general conformance |

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

## Versioned approval and evidence

New wrapper promotion requires `wss-python-promotion/v2`:

```json
{
  "schema": "wss-python-promotion/v2",
  "candidate": {"repository": "cwru-non-academic/WSSCore", "commit": "FULL_SHA", "run_id": "ID", "artifact_id": "ID", "archive": "WSS-Universal-ci.zip", "sha256": "SHA256"},
  "wrapper": {"source_sha": "FULL_SHA", "preflight_run_id": "ID"},
  "cli": {"source_sha": "FULL_SHA", "preflight_run_id": "ID"},
  "ros": {"source_sha": "FULL_SHA", "preflight_run_id": "ID"},
  "fixture": {"commit": "7145e2307f997f703748530bf74311ef94455e98", "sha256": "1cdfb9448a1776011eadc9aef8356362216032013a4f268f50242746c50a0b44"},
  "projection_sha256": "SHA256"
}
```

The canonical PR marker is `<!-- wss-python-approval:v2 BASE64 -->`, where
BASE64 is UTF-8 of the normalized, ordered compact approval JSON. Legacy v1
approvals remain readable for already-issued CLI requests; they cannot authorize
a new wrapper promotion or ROS promotion.

All three candidate acceptance jobs must pass before a new wrapper dependency PR.
Wrapper/CLI evidence remains `wss-python-evidence/v1`, artifact
`python-preflight-evidence`, exactly four files: `evidence.json`, `results.xml`,
`dotnet.log`, `projection.json`. ROS uses that same artifact/envelope, with role
`ros`, `wrapper_sha`, `ros_sha`, and its exact own `run_sha`/repository/run ID.
Wrapper/CLI bind their wrapper/CLI source pair independently; ROS binds its
wrapper/ROS pair. The v2 approval binds all three sources and the same candidate,
fixture and payload digest. CLI does not depend on ROS source at runtime.

Evidence must record actual pythonnet execution (`execution: pythonnet`,
`python_executed: true`), SDK 9.0.316, net9.0, NUnit 3.14.0, Python 3.12,
pythonnet 3.0.5, ten exact canonical cases discovered/executed/passed, zero
failures/skips, eighteen unchanged assertion expressions, fixture identity,
candidate identity, projection digest and XML/log SHA256 values. ROS must generate
real canonical NUnit results through its production path. No stubbed ROS result,
CLI-only proof or generated green summary substitutes for that evidence.

`projection.json` uses the existing `wss-python-projection/v1` complete universal
inventory and file hashes. The released payload is never rebuilt or overlaid.

## Independent application promotion

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
