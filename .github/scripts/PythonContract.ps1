Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Universal-WssFiles.ps1"
$PythonWrapperRepository = 'cwru-non-academic/Python_WSS_Integration_Lib'
$PythonCliRepository = 'cwru-non-academic/CLI_Python_WSS_Application'
$PythonRosRepository = 'cwru-non-academic/ROS_Python_WSS_Application'
$PythonApplications = [ordered]@{
    cli = [pscustomobject]@{ role='cli'; repository=$PythonCliRepository; gitlink='external/wss-py-wrapper'; source_field='cli_sha'; acceptance='CLI general conformance' }
    ros = [pscustomobject]@{ role='ros'; repository=$PythonRosRepository; gitlink='HFI_WSS_Python_Interface'; source_field='ros_sha'; acceptance='ROS general conformance' }
}
function Get-PythonApplication([ValidateSet('cli','ros')][string]$Role) {
    $PythonApplications[$Role]
}
$PythonGitlink = 'external/wss-py-wrapper'
$PythonPluginPath = 'Cs_Libraries'
$PythonProjectionFiles = @($WssUniversalFiles)

function Invoke-PythonGh([string[]]$Arguments) {
    $response = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub operation failed: $($Arguments[0..([Math]::Min(1,$Arguments.Count-1))] -join ' ')" }
    $response
}
function Invoke-PythonGit([string]$Root, [string[]]$Arguments) {
    $response = & git -C $Root @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Git operation failed: $($Arguments[0])" }
    $response
}
function Assert-PythonSha([string]$Sha) {
    if ($Sha -cnotmatch '^[0-9a-f]{40}$') { throw 'A full lowercase source SHA is required.' }
}
function Assert-PythonCandidate($Candidate) {
    if ($Candidate.repository -cne 'cwru-non-academic/WSSCore') { throw 'Unexpected producer.' }
    Assert-PythonSha $Candidate.commit
    foreach ($field in @('run_id','artifact_id')) {
        if ([string]$Candidate.$field -cnotmatch '^[1-9][0-9]*$') { throw "Invalid candidate $field." }
    }
    if ($Candidate.archive -cnotmatch '^WSS-Universal-[A-Za-z0-9._-]+\.zip$' -or
        $Candidate.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid archive/hash.' }
}
function Assert-PythonSameCandidate($Actual, $Expected) {
    Assert-PythonCandidate $Actual
    foreach ($field in @('repository','commit','run_id','artifact_id','archive','sha256')) {
        if ([string]$Actual.$field -cne [string]$Expected.$field) { throw "Candidate mismatch: $field" }
    }
}
function Get-PythonProjectionDigest($Files) {
    $text = @($Files | Sort-Object { [string]$_.source } | ForEach-Object { "$($_.source)|$($_.sha256)" }) -join "`n"
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
}
function Assert-PythonProjection([string]$Root, $Record) {
    if ($Record.schema -cne 'wss-python-projection/v1') { throw 'Invalid Python payload schema.' }
    Assert-PythonCandidate $Record.candidate
    $actual = @(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/') })
    if (@(Compare-Object $PythonProjectionFiles $actual -CaseSensitive).Count -ne 0 -or $Record.files.Count -ne $PythonProjectionFiles.Count -or
        @(Compare-Object $PythonProjectionFiles @($Record.files.source) -CaseSensitive).Count -ne 0) { throw 'Exact full universal inventory required; no fallback/extra files.' }
    foreach ($item in $Record.files) {
        if ((Get-FileHash -LiteralPath (Join-Path $Root $item.source)).Hash.ToLowerInvariant() -cne $item.sha256) { throw "Payload hash mismatch: $($item.source)" }
    }
    if ((Get-PythonProjectionDigest $Record.files) -cne $Record.projection_sha256) { throw 'Payload digest mismatch.' }
}
function New-PythonProjection([string]$ArtifactRoot, [string]$WrapperRoot, [string]$Destination, $Candidate) {
    Assert-PythonCandidate $Candidate
    if (Test-Path -LiteralPath $Destination) { throw 'Payload destination must be new.' }
    $inventory = @(Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($ArtifactRoot,$_.FullName).Replace('\','/') })
    if (@(Compare-Object $PythonProjectionFiles $inventory -CaseSensitive).Count -ne 0) { throw 'Exact full universal inventory required.' }
    New-Item -ItemType Directory -Path $Destination | Out-Null
    $files = @()
    foreach ($source in $PythonProjectionFiles) {
        $target = Join-Path $Destination $source
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $ArtifactRoot $source) -Destination $target
        $files += [ordered]@{ source=$source; sha256=(Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() }
    }
    $record = [pscustomobject][ordered]@{ schema='wss-python-projection/v1'; candidate=$Candidate; projection_sha256=(Get-PythonProjectionDigest $files); files=$files }
    Assert-PythonProjection $Destination $record
    $record
}
function Read-PythonConfig([string]$Path) {
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($config.schema -cne 'wss-python-ci/v1' -or $config.branch -cne 'dev' -or $config.automated_execution -cne 'pythonnet' -or
        $config.python_version -cne '3.12' -or $config.pythonnet_version -cne '3.0.5' -or
        $config.fixture_repository -cne 'cwru-non-academic/CSharp_WSS_Integration_Lib' -or $config.dotnet_expected_cases.Count -ne 10) { throw 'Unexpected Python CI contract.' }
    Assert-PythonSha $config.fixture_commit
    if ($config.fixture_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Missing fixture digest.' }
    $config
}
function Assert-PythonResults([string]$Path, $Config, [switch]$DotNet) {
    # Disable DTD/entity resolution: results may originate from proposed source.
    $settings = [Xml.XmlReaderSettings]::new(); $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit; $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path,$settings)
    try { $xml=[Xml.XmlDocument]::new(); $xml.XmlResolver=$null; $xml.Load($reader) } finally { $reader.Dispose() }
    $run=$xml.DocumentElement; $cases=@($xml.SelectNodes('//test-case'))
    if ($run.get_Name() -cne 'test-run' -or $run.GetAttribute('result') -cne 'Passed' -or
        $run.GetAttribute('testcasecount') -cne '10' -or $run.GetAttribute('total') -cne '10' -or
        $run.GetAttribute('passed') -cne '10' -or $cases.Count -ne 10) { throw 'All ten canonical cases must be discovered, executed and passed.' }
    foreach ($attribute in @('failed','skipped','inconclusive')) { if ($run.GetAttribute($attribute) -cne '0') { throw "Nonzero or absent $attribute count." } }
    $expected=if ($DotNet) { @($Config.dotnet_expected_cases) } else { @($Config.expected_cases) }
    if ($expected.Count -ne 10 -or @(Compare-Object $expected @($cases | ForEach-Object { $_.GetAttribute('name') }) -CaseSensitive).Count -ne 0 -or
        @($cases | Where-Object { $_.GetAttribute('result') -cne 'Passed' }).Count -gt 0) { throw 'Missing/duplicate/unexpected/unsuccessful canonical cases.' }
}
function Assert-PythonSource([string]$Root,[string]$Sha,[switch]$IgnoreSubmodule) {
    Assert-PythonSha $Sha
    if ((Invoke-PythonGit $Root @('rev-parse','HEAD')).Trim() -cne $Sha) { throw 'Checked-out source differs from the pinned SHA.' }
    $statusArguments=@('status','--porcelain','--untracked-files=normal')
    if ($IgnoreSubmodule) { $statusArguments+='--ignore-submodules=all' }
    if (@(Invoke-PythonGit $Root $statusArguments).Count -ne 0) { throw 'Source checkout must be clean before staging the disposable harness.' }
}
function Get-PythonAllowedWrapperPaths {
    @($PythonProjectionFiles | ForEach-Object { "$PythonPluginPath/$_" }) + @('.github/python-candidate.json')
}
function Assert-PythonDiff([string[]]$Paths,[string[]]$Allowed) {
    if ($Paths.Count -eq 0 -or @($Paths | Where-Object { $_ -cnotin $Allowed }).Count -gt 0) { throw 'Empty or out-of-scope promotion diff.' }
}
