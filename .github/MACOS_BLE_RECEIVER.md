# macOS BLE receiver preparation

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
macOS alongside the unchanged ten-case/eighteen-assertion shared Core conformance.
For a new producer, proof requires all three platform jobs and hash/source/run-bound
native smoke reports. Canonical producer proof additionally requires:

- `Build macOS universal BLE bridge`
- `BLE consumer (macOS arm64)`
- `BLE consumer (macOS x86_64)`

The existing successful `artifacts.yml` **push to dev**, dev ancestry, exact
run/artifact/archive/checksum and whole-run-success requirements remain intact.
An otherwise green Core PR run is rejected. The reviewed Core PR #15 artifact
(`40749828245` / `12843059112`, SHA256
`e0862dc5165c1790853f5d30a6fe1221fbe7d90295bc2ff5c48f465e903cddf8`)
can be used for integrity-checked local receiver verification; such evidence is
not candidate-preflight approval and cannot authorize automatic publication.

## Coordinated rollout boundary

Do not promote the new payload until the macOS-aware C# fixture is reviewed and
pinned here, both receiver preparations reach the intended dev branches through
reviewed PRs, and the parent coordinates the Core merge. A merge into Core main
does not create canonical dev-push proof by itself: the reviewed feature must be
included in dev through the approved branch workflow, then the genuine dev-push
artifact must pass its own complete producer run. Use that new immutable tuple,
not the PR tuple above, for existing preflight/promotion entry points.

The current v2 Python wrapper promotion still requires independent wrapper, CLI
and ROS proofs and later dispatches both applications. That requirement has not
been relaxed to manufacture a CLI-only success. ROS receiver readiness and any
limited traversal must be coordinated before dispatch. This preparation changes
no GitHub App permissions, credentials, rulesets, merges or dispatches.
