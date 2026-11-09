$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$lines=Get-Content (Join-Path $root '.github/workflows/_python-validation.yml')
$seen=$false; $collect=$false; $body=@()
foreach ($line in $lines) {
    if ($line.Trim() -ceq 'id: sources') { $seen=$true; continue }
    if ($seen -and $line.Trim() -ceq 'run: |') { $collect=$true; continue }
    if (!$collect) { continue }
    if ($line.StartsWith('          ')) { $body+=$line.Substring(10) }
    elseif (!$line.Trim()) { $body+=''; continue }
    else { break }
}
if (!$body.Count) { throw 'Actual candidate readiness workflow block not found.' }
$check=[scriptblock]::Create($body -join "`n")
$tempParent=[IO.Path]::GetTempPath()
if(!$IsWindows){Push-Location $tempParent;try{$tempParent=(& /bin/pwd -P).Trim();if($LASTEXITCODE -ne 0 -or !$tempParent){throw 'Cannot resolve physical fixture parent.'}}finally{Pop-Location}}
$tempParent=[IO.Path]::GetFullPath($tempParent).TrimEnd([IO.Path]::DirectorySeparatorChar)
$temp=Join-Path $tempParent ('wss-candidate-readiness-'+[guid]::NewGuid().ToString('N'))
function Assert-Rejected([scriptblock]$Action,[string]$ExpectedMessage,[string]$Case) {
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -cne $ExpectedMessage) { throw }
        return
    }
    throw "Candidate readiness unexpectedly accepted: $Case"
}
$rejections=@{
    'own-execution'='Unexpected automated execution contract.'
    'own-sdk'='Unexpected automated execution contract.'
    'own-opt-out'='Candidate promotion baseline approval remains pending; ordinary committed-state .NET CI is separate.'
    'wrapper-opt-out'='Candidate promotion baseline approval remains pending; ordinary committed-state .NET CI is separate.'
    'source-mismatch'='Invalid or raced immutable source.'
    'mutable-wrapper'='Candidate preflight requires exact target source SHAs.'
    'main-opt-out'='Main candidate capability has not been adopted.'
    'invalid-role'='Invalid validation role/mode.'
    'invalid-mode'='Invalid validation role/mode.'
}
$null=New-Item -ItemType Directory -Path (Join-Path $temp 'caller/.github'),(Join-Path $temp 'candidate-contract/.github') -Force
$keys=@('MODE','ROLE','WRAPPER_SHA','CLI_SHA','GUI_SHA','GITHUB_SHA','GITHUB_REF','GITHUB_OUTPUT')
$previous=@{}; foreach ($key in $keys) { $previous[$key]=[Environment]::GetEnvironmentVariable($key) }
Push-Location $temp
try {
    foreach ($case in @('valid','valid-main','own-execution','own-sdk','own-opt-out','wrapper-opt-out','source-mismatch','mutable-wrapper','main-opt-out','invalid-role','invalid-mode')) {
        $own=Get-Content (Join-Path $root '.github/python-ci.json') -Raw | ConvertFrom-Json
        $candidate=$own | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $own.baseline_ready=$true; $candidate.baseline_ready=$true
        # Applications may still run their exact legacy ordinary case inventory.
        $own.dotnet_expected_cases=@($own.dotnet_expected_cases | Select-Object -First 10)
        $env:MODE='candidate'; $env:ROLE='cli'; $env:WRAPPER_SHA=('a'*40)
        $env:CLI_SHA=('b'*40); $env:GUI_SHA=('b'*40); $env:GITHUB_SHA=('b'*40)
        $env:GITHUB_REF='refs/heads/dev'; $env:GITHUB_OUTPUT=Join-Path $temp ($case+'.outputs')
        switch ($case) {
            'valid-main' { $env:GITHUB_REF='refs/heads/main' }
            'invalid-role' { $env:ROLE='unsupported' }
            'invalid-mode' { $env:MODE='unsupported' }
            'own-execution' { $own.automated_execution='unsupported' }
            'own-sdk' { $own.dotnet_sdk='9.0.999' }
            'own-opt-out' { $own.baseline_ready=$false }
            'wrapper-opt-out' { $candidate.baseline_ready=$false }
            'source-mismatch' { $env:GITHUB_SHA=('c'*40) }
            'mutable-wrapper' { $env:WRAPPER_SHA='dev' }
            'main-opt-out' { $own.channels=@('dev'); $env:GITHUB_REF='refs/heads/main' }
        }
        $own | ConvertTo-Json -Depth 12 | Set-Content 'caller/.github/python-ci.json'
        $candidate | ConvertTo-Json -Depth 12 | Set-Content 'candidate-contract/.github/python-ci.json'
        if ($rejections.ContainsKey($case)) {
            Assert-Rejected $check $rejections[$case] $case
        } else {
            & $check | Out-Null
            if (!(Select-String -LiteralPath $env:GITHUB_OUTPUT -SimpleMatch "fixture=$($candidate.fixture_commit)" -Quiet)) { throw 'Candidate fixture was not selected from the exact wrapper contract.' }
        }
    }
    # An unexpected setup error must remain an error, not satisfy an opt-out case.
    Move-Item -LiteralPath 'caller/.github/python-ci.json' -Destination (Join-Path $temp 'wrong-layout.json')
    $unexpected=$null
    try { Assert-Rejected $check $rejections['own-opt-out'] 'missing caller layout' } catch { $unexpected=$_ }
    if (!$unexpected -or $unexpected.FullyQualifiedErrorId -notlike 'PathNotFound*' -or $unexpected.TargetObject -notlike '*caller*python-ci.json') { throw 'Missing caller configuration was not preserved as the original file error.' }
} finally {
    Pop-Location
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$previous[$key]) }
    $resolved=[IO.Path]::GetFullPath($temp)
    if([IO.Path]::GetDirectoryName($resolved) -cne $tempParent -or [IO.Path]::GetFileName($resolved) -cnotmatch '^wss-candidate-readiness-[a-f0-9]{32}$'){throw 'Unsafe candidate fixture cleanup path'}
    if((Get-Item -LiteralPath $resolved -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Redirected candidate fixture cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output 'PASS: actual candidate workflow retains application/wrapper opt-in and immutable source gates; metadata only.'
