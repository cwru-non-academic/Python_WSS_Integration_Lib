. "$PSScriptRoot/../MacOSConsumerEvidence.ps1"
$repository='cwru-non-academic/CLI_Python_WSS_Application';$runId='100';$sourceSha='c'*40
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('wss-macos-policy-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$checks=0
function New-PairFixture([string]$Name) {
    $root=Join-Path $temporary $Name;New-Item -ItemType Directory -Path $root | Out-Null
    foreach($arch in @('x64','arm64')) {
        $folder=Join-Path $root $arch;New-Item -ItemType Directory -Path $folder | Out-Null
        @{schema='wss-macos-worker/v1';architecture=$arch;conclusion='success';repository=$repository;run_id=$runId;source_sha=$sourceSha} | ConvertTo-Json | Set-Content (Join-Path $folder 'outcome.json')
        @{schema='wss-python-smoke/v2';os='darwin';architecture=$arch;dotnet_process_architecture=$arch;os_architecture=$arch;runner_architecture=$arch;translated=$false;execution='native';physical_io=$false;macos_ble_declared=$true;contract='macos-ble-v1';cli_routing=$true;ble='passed: policy fixture, not native proof'} | ConvertTo-Json | Set-Content (Join-Path $folder 'python-smoke.json')
        '<TestRun><Results><UnitTestResult testName="FacadeLoadsCurrentPlatformBackendAndDependencies" outcome="Passed" /></Results></TestRun>' | Set-Content (Join-Path $folder 'platform.trx')
        @{schema='wss-python-platform/v2';run_repository=$repository;run_id=$runId;run_sha=$sourceSha;os='macOS 15 policy fixture';architecture=$arch;execution='native';mode='candidate';wrapper_sha=('a'*40);cli_sha=$sourceSha;fixture_sha=('b'*40);projection_sha256=('d'*64);universal_contract='macos-ble-v1';candidate=@{repository='cwru-non-academic/WSSCore';commit=('e'*40);run_id='1';artifact_id='2';archive='WSS-Universal-ci.zip';sha256=('f'*64)};ble='passed: policy fixture, not native proof';python_smoke_sha256=(Get-FileHash (Join-Path $folder 'python-smoke.json')).Hash.ToLowerInvariant();platform_trx_sha256=(Get-FileHash (Join-Path $folder 'platform.trx')).Hash.ToLowerInvariant()} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $folder 'platform.json')
    }
    Get-WssMacOSPair $root $repository $runId $sourceSha | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $root 'macos.json')
    $root
}
function Reject-Pair([string]$Root,[string]$Reason,[string]$ExpectedMessage='') {
    $caught=$false
    try {$null=Assert-WssMacOSPair $Root $repository $runId $sourceSha}
    catch {$caught=$true;if($ExpectedMessage -and !$_.Exception.Message.Contains($ExpectedMessage)) {throw "Wrong diagnostic for $Reason`: $($_.Exception.Message)"}}
    if(!$caught) {throw "Accepted invalid macOS pair: $Reason"}
    $script:checks++
}
function Change-Json([string]$Path,[string]$Field,$Value) {
    $json=Get-Content $Path -Raw | ConvertFrom-Json;$json.$Field=$Value;$json | ConvertTo-Json -Depth 12 | Set-Content $Path
}
$root=New-PairFixture 'valid';$null=Assert-WssMacOSPair $root $repository $runId $sourceSha;$checks++
foreach($field in @('architecture','run_sha','run_repository','projection_sha256','wrapper_sha','fixture_sha','schema','execution')) {
    $root=New-PairFixture ('proof-'+$field)
    Change-Json (Join-Path $root 'arm64/platform.json') $field 'incorrect'
    Reject-Pair $root $field 'arm64'
}
foreach($field in @('architecture','dotnet_process_architecture','os_architecture','runner_architecture')) {
    $root=New-PairFixture ('identity-'+$field)
    Change-Json (Join-Path $root 'arm64/python-smoke.json') $field 'x64'
    Reject-Pair $root $field 'arm64'
}
$root=New-PairFixture 'translated';Change-Json (Join-Path $root 'x64/python-smoke.json') translated $true;Reject-Pair $root 'Rosetta cannot count as native Intel' 'Intel'
foreach($result in @('failure','skipped','cancelled')) {
    $root=New-PairFixture $result;Change-Json (Join-Path $root 'arm64/outcome.json') conclusion $result;Reject-Pair $root $result 'arm64'
}
$root=New-PairFixture 'wrong-run';Change-Json (Join-Path $root 'arm64/outcome.json') run_id '101';Reject-Pair $root 'another run' 'arm64'
$root=New-PairFixture 'missing';Remove-Item -LiteralPath (Join-Path $root 'arm64/platform.json');Reject-Pair $root 'missing architecture evidence'
$root=New-PairFixture 'skip-native'
'<TestRun><Results><UnitTestResult testName="FacadeLoadsCurrentPlatformBackendAndDependencies" outcome="NotExecuted" /></Results></TestRun>' | Set-Content (Join-Path $root 'arm64/platform.trx')
Change-Json (Join-Path $root 'arm64/platform.json') platform_trx_sha256 ((Get-FileHash (Join-Path $root 'arm64/platform.trx')).Hash.ToLowerInvariant())
Reject-Pair $root 'skipped native fixture' 'arm64'
$root=New-PairFixture 'manifest';Change-Json (Join-Path $root 'macos.json') source_sha ('9'*40);Reject-Pair $root 'tampered aggregate'
$root=New-PairFixture 'extra';Set-Content (Join-Path $root 'extra.json') '{}';Reject-Pair $root 'extra artifact bytes'
$root=New-PairFixture 'legacy'
foreach($arch in @('x64','arm64')) {
    Change-Json (Join-Path $root "$arch/python-smoke.json") macos_ble_declared $false
    Change-Json (Join-Path $root "$arch/python-smoke.json") contract 'legacy-v1'
    Change-Json (Join-Path $root "$arch/python-smoke.json") ble 'unsupported: legacy payload has no macOS BLE'
    Change-Json (Join-Path $root "$arch/platform.json") universal_contract 'legacy-v1'
    Change-Json (Join-Path $root "$arch/platform.json") ble 'unsupported: legacy payload has no macOS BLE'
    Change-Json (Join-Path $root "$arch/platform.json") python_smoke_sha256 ((Get-FileHash (Join-Path $root "$arch/python-smoke.json")).Hash.ToLowerInvariant())
}
$legacy=Get-WssMacOSPair $root $repository $runId $sourceSha
if(@($legacy.architectures | Where-Object coverage -CNE 'legacy-no-macos-ble').Count) {throw 'Legacy compatibility must never claim native BLE coverage'}
$checks++
$root=New-PairFixture 'candidate-mismatch'
$proof=Get-Content (Join-Path $root 'arm64/platform.json') -Raw | ConvertFrom-Json
$proof.candidate.sha256='0'*64;$proof | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'arm64/platform.json')
Reject-Pair $root 'different architecture candidate' 'arm64'
Write-Output "PASS: $checks macOS pair policy checks. These fixtures do not execute native BLE or establish architecture coverage."
# Keep the small fixture directory for diagnostic inspection; it contains no executable artifacts.
