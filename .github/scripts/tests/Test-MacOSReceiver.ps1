$ErrorActionPreference='Stop'
. "$PSScriptRoot/../PythonPromotion.ps1"
$checks=0
function Require([bool]$Value,[string]$Description) { if (!$Value) { throw $Description }; $script:checks++ }
function Reject([scriptblock]$Action,[string]$Description) { $failed=$false; try { & $Action | Out-Null } catch { $failed=$true }; Require $failed $Description }
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$record=Get-Content (Join-Path $root '.github/python-candidate.json') -Raw | ConvertFrom-Json
Assert-PythonProjection (Join-Path $root 'Cs_Libraries') $record
Require ((Get-WssUniversalContract @(Get-PythonProjectionFiles $record)) -ceq 'legacy-v1') 'Committed transition baseline must remain the exact legacy payload.'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('wss-macos-receiver-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$inputRoot=Join-Path $temporary 'input'
Copy-Item -LiteralPath (Join-Path $root 'Cs_Libraries') -Destination $inputRoot -Recurse
$mac=Join-Path $inputRoot 'backends/macos'
New-Item -ItemType Directory -Path $mac | Out-Null
# Deliberate non-library fixtures test inventory rules only; never loading proof.
Set-Content (Join-Path $mac 'WSS.Transport.BLE.MacOS.dll') 'contract-only-managed-placeholder'
Reject { New-PythonProjection $inputRoot $root (Join-Path $temporary 'partial') $record.candidate } 'A partial macOS pair must fail.'
Set-Content (Join-Path $mac 'libwss_macos_ble.dylib') 'contract-only-native-placeholder'
$projected=Join-Path $temporary 'projected'
$new=New-PythonProjection $inputRoot $root $projected $record.candidate
Require ($new.universal_contract -ceq 'macos-ble-v1' -and $new.files.Count -eq 27) 'The new contract must explicitly declare all 27 files.'
Assert-PythonProjection $projected $new
Require ((Get-FileHash (Join-Path $projected 'backends/macos/libwss_macos_ble.dylib')).Hash -ceq (Get-FileHash (Join-Path $mac 'libwss_macos_ble.dylib')).Hash) 'Projection must retain the native dylib byte-for-byte.'
$bad=$new | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$bad.universal_contract='legacy-v1'
Reject { Get-PythonProjectionFiles $bad } 'A new inventory cannot masquerade as legacy.'
$bad=$record | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$bad | Add-Member -NotePropertyName universal_contract -NotePropertyValue 'macos-ble-v1'
Reject { Assert-PythonProjection (Join-Path $root 'Cs_Libraries') $bad } 'A declared macOS payload cannot omit either backend asset.'
Remove-Item -LiteralPath (Join-Path $projected 'backends/macos/libwss_macos_ble.dylib')
Reject { Assert-PythonProjection $projected $new } 'Missing declared dylib must fail.'
Set-Content (Join-Path $mac 'extra.dll') 'not allowlisted'
Reject { New-PythonProjection $inputRoot $root (Join-Path $temporary 'extra') $record.candidate } 'Arbitrary extra files remain forbidden.'
$baseNames=@('Build and validate artifacts','Core conformance','Serial consumer (Windows)','Serial consumer (macOS)','Serial consumer (Linux)','BLE consumer (Windows)','BLE consumer (Linux)','Core consumer (Windows)','Core consumer (macOS)','Core consumer (Linux)','Start routine downstream validation')
$baseJobs=@($baseNames | ForEach-Object { [pscustomobject]@{name=$_;conclusion='success'} })
Assert-PythonProducerJobs $baseJobs 'legacy-v1'; $checks++
Reject { Assert-PythonProducerJobs $baseJobs 'macos-ble-v1' } 'Legacy producer gates cannot approve a declared macOS payload.'
$macNames=@('Build macOS universal BLE bridge','BLE consumer (macOS arm64)','BLE consumer (macOS x86_64)')
$allJobs=$baseJobs+@($macNames | ForEach-Object { [pscustomobject]@{name=$_;conclusion='success'} })
Assert-PythonProducerJobs $allJobs 'macos-ble-v1'; $checks++
foreach ($name in $macNames) {
    Reject { Assert-PythonProducerJobs @($allJobs | Where-Object name -CNE $name) 'macos-ble-v1' } "Missing required producer gate must fail: $name"
}
$badJobs=$allJobs | ConvertTo-Json | ConvertFrom-Json
($badJobs | Where-Object name -CEQ 'BLE consumer (macOS arm64)').conclusion='skipped'
Reject { Assert-PythonProducerJobs $badJobs 'macos-ble-v1' } 'Skipped macOS architecture proof must fail.'
Reject { Assert-PythonProducerJobs ($allJobs+@($allJobs[-1])) 'macos-ble-v1' } 'Duplicate producer proof must fail.'
# An otherwise green PR run is still not a canonical dev-push producer.
function Invoke-PythonGh([string[]]$Arguments) {
    if ($Arguments[-1] -notlike '*actions/runs/*') { throw 'A PR source must be rejected before any further lookup.' }
    @{repository=@{full_name='cwru-non-academic/WSSCore'};path='.github/workflows/artifacts.yml';head_sha=$record.candidate.commit;event='pull_request';status='completed';conclusion='success'} | ConvertTo-Json -Depth 5
}
Reject { Assert-PythonProducer $record.candidate } 'Green PR artifacts remain ineligible for automatic promotion.'
Write-Output "PASS: $checks macOS receiver inventory/proof rejection checks; no native activation is claimed by these fixtures."
