# Trusted Python capability profiles

This is an additive bootstrap. Historical Invoke-DotNetConformance.ps1 and its
strict sixteen-case guards remain unchanged. Invoke-ProfiledPythonConformance.ps1
verifies the exact universal projection first, then inspects PE metadata without
loading/executing the candidate assembly. Product config supplies only independently
validated runtime/readiness/channel settings, never the profile or case inventory.

The bounded reviewed legacy identity is Core 76803c03c7aa55b8951499053641ad9ce83504b8,
DLL SHA256 738691490a76ceb56b38aa580148116db1a46601117246890a129eb0e6bfed20,
archive SHA256 856566f5710a5662254373cc8c5d3ecf3527b89506f0df140824261ca50d2167,
run 42230527501, artifact 13507483694. It requires all original scenario and
conformance APIs and no modern sentinel types. Other legacy producers fail closed.
Modern requires all six sentinel types, both original and layered catalogs,
reload operations, configuration snapshot members, and window/result APIs.
Any partial fingerprint fails before test execution. Future modern producers
still require existing caller producer/archive authentication and exact projection
checks; this module is not a replacement for those boundaries.

The bootstrap owns exact Git/LF fixture bytes (-text attributes preserve hashes):
- legacy-v1: CSharp 02172a64c55becd5535204f46f10b4755bf3ee05,
  f6aeced83d35255532b6685d9c870307f856aad140da133695a77e9de6104ee2,
  ten original cases, eighteen assertions, single stage.
- layered-v1: CSharp fc427c5b8bc6534a7d02f00283830072572aa03a,
  96812ab33be7ede8840ddb78131a50796fd3f797d9627f958251b3e58796baf8,
  sixteen single plus sixteen multi cases, twenty assertions per stage.

Only the factory/alias is adapted for production Python. The trusted staging script
copies the adapter from the independently selected conformance directory; selected
build projects or bootstrap scripts cannot replace mandatory canonical assertions.
The test-only conformance/profile-contract.json declares both supported inventories
but cannot choose a payload profile or weaken fixtures/counts/assertions.

Only an authenticated selection-enabled campaign requires layered-v1. The
WithContext bridge obtains that scope after Core inspect; run-level selections
and legacy producer policies retain complete legacy coverage when appropriate.
Raw caller-supplied IDs and switches do not authenticate campaigns.

Evidence schema wss-python-profile-evidence/v1 binds profile, producer_commit,
core_dll_sha256, the full producer identity, actual wrapper/CLI SHAs, selected test
identity, immutable fixture hash, projection digest and result/log hashes.
Assert-PythonProfileEvidence revalidates fixed inventory and profile identity,
including both mandatory modern stages. There is no count-based fallback.

Actual Python remote main 13ae9695ee41834984e374ff73444fece179e93e was independently
fetched and its full committed projection verified. Legacy ten tests passed.
The held modern wrapper d9e316f9d803f883e8671511ddd3cba435a829db passed sixteen plus
sixteen with the c0184c7efeead51373baace278f6370966fa9016bed7ad76c627cea4aa982528 DLL.
Local metadata/corruption tests are not hosted campaign authentication evidence.
