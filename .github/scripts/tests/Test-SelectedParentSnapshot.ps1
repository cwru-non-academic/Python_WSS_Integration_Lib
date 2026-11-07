$ErrorActionPreference='Stop'
. "$PSScriptRoot/../SelectedParentSnapshot.ps1"
$temp=Join-Path ([IO.Path]::GetTempPath()) ('selected-parent-snapshot-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$temp=(& python -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' $temp).Trim()
$child=Join-Path $temp 'mutate.ps1'
@'
param([string]$Case,[string]$Root)
$ErrorActionPreference='Stop'
switch($Case){
 'core-edit' {'changed' | Set-Content -LiteralPath "$Root/core/code.mjs"}
 'core-add' {'added' | Set-Content -LiteralPath "$Root/core/added.mjs"}
 'core-delete' {Remove-Item -LiteralPath "$Root/core/code.mjs"}
 'lock' {'changed' | Set-Content -LiteralPath "$Root/caller/wss-ci.lock.json"}
 'context' {'changed' | Set-Content -LiteralPath "$Root/context.json"}
 'roots' {'changed' | Set-Content -LiteralPath "$Root/roots.json"}
 'baseline-edit' {'changed' | Set-Content -LiteralPath "$Root/baseline/results.xml"}
 'baseline-add' {'added' | Set-Content -LiteralPath "$Root/baseline/extra.json"}
 'baseline-delete' {Remove-Item -LiteralPath "$Root/baseline/results.xml"}
 'baseline-directory' {$null=New-Item -ItemType Directory -Path "$Root/baseline/added"}
 'redirect-child' {
   $kind=if($IsWindows){'Junction'}else{'SymbolicLink'}
   $null=New-Item -ItemType $kind -Path "$Root/baseline/redirect" -Target "$Root/core"
 }
 'redirect-root' {
   Move-Item -LiteralPath "$Root/baseline" -Destination "$Root/original"
   $kind=if($IsWindows){'Junction'}else{'SymbolicLink'}
   $null=New-Item -ItemType $kind -Path "$Root/baseline" -Target "$Root/original"
 }
 default {throw 'Unknown mutation'}
}
'@ | Set-Content -LiteralPath $child

$cases=@('core-edit','core-add','core-delete','lock','context','roots','baseline-edit','baseline-add','baseline-delete','baseline-directory','redirect-child','redirect-root')
foreach($case in $cases){
    $root=Join-Path $temp $case
    foreach($dir in @('core','caller','baseline')){$null=New-Item -ItemType Directory -Path "$root/$dir" -Force}
    foreach($file in @('core/code.mjs','caller/wss-ci.lock.json','baseline/results.xml','context.json','roots.json')){'original' | Set-Content -LiteralPath "$root/$file"}
    $snapshot=New-SelectedParentSnapshot @("$root/core","$root/caller","$root/baseline") @("$root/context.json","$root/roots.json")
    Assert-SelectedParentSnapshot $snapshot
    & (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source -NoProfile -NonInteractive -File $child -Case $case -Root $root
    if($LASTEXITCODE -ne 0){throw "Mutation child failed: $case"}
    $rejected=$false;try{Assert-SelectedParentSnapshot $snapshot}catch{$rejected=$true}
    if(!$rejected){throw "Accepted changed parent inputs: $case"}
}
Write-Output 'PASS: 12 actual-child authority/baseline mutations rejected after positive controls; no synthetic Core authentication claimed.'
