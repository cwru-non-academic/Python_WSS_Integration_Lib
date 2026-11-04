param(
    [Parameter(Mandatory)][string]$InputRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$ArtifactPrefix,
    [string]$EvidenceSubdirectory='',
    [Parameter(Mandatory)][string]$WorkerResult
)
. "$PSScriptRoot/MacOSConsumerEvidence.ps1"
if(Test-Path -LiteralPath $OutputRoot) {throw 'macOS aggregate output must be new'}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$copyErrors=@()
foreach($architecture in @('x64','arm64')) {
    $from=Join-Path $InputRoot "$ArtifactPrefix-macOS-$architecture"
    if($EvidenceSubdirectory) {$from=Join-Path $from $EvidenceSubdirectory}
    $to=Join-Path $OutputRoot $architecture
    New-Item -ItemType Directory -Path $to | Out-Null
    foreach($name in @('outcome.json','platform.json','python-smoke.json','platform.trx')) {
        $file=Join-Path $from $name
        if(Test-Path -LiteralPath $file -PathType Leaf) {Copy-Item -LiteralPath $file -Destination (Join-Path $to $name)}
        else {$copyErrors+="macOS $architecture`: missing $name"}
    }
}
try {
    if($copyErrors.Count) {throw ($copyErrors -join '; ')}
    $manifest=Get-WssMacOSPair $OutputRoot $env:GITHUB_REPOSITORY $env:GITHUB_RUN_ID $env:GITHUB_SHA
    if($WorkerResult -cne 'success') {throw 'A macOS architecture worker did not complete successfully; inspect its named Intel/Apple Silicon job. Valid-looking reports cannot override a failed/cancelled worker.'}
    $manifest | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutputRoot 'macos.json')
    $summary="## macOS consumer`n`n| Architecture | Execution | Coverage |`n|---|---|---|`n"
    foreach($item in $manifest.architectures) {
        $label=if($item.architecture -ceq 'x64') {'Intel (x64)'} else {'Apple Silicon (arm64)'}
        $summary+="| $label | native: passed | $($item.coverage) |`n"
    }
    if($env:GITHUB_STEP_SUMMARY) {Add-Content $env:GITHUB_STEP_SUMMARY $summary}
    Write-Output $summary
} catch {
    if($env:GITHUB_STEP_SUMMARY) {Add-Content $env:GITHUB_STEP_SUMMARY "## macOS consumer failed`n`n$($_.Exception.Message)"}
    throw
}
