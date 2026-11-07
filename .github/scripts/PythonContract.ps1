Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Universal-WssFiles.ps1"
$PythonWrapperRepository = 'cwru-non-academic/Python_WSS_Integration_Lib'
$PythonCliRepository = 'cwru-non-academic/CLI_Python_WSS_Application'
$PythonRosRepository = 'cwru-non-academic/ROS_Python_WSS_Application'
$PythonApplications = [ordered]@{
    cli = [pscustomobject]@{ role='cli'; repository=$PythonCliRepository; gitlink='external/wss-py-wrapper'; source_field='cli_sha'; acceptance='CLI general conformance' }
    ros = [pscustomobject]@{ role='ros'; repository=$PythonRosRepository; gitlink='HFI_WSS_Python_Interface'; source_field='ros_sha'; acceptance='ROS compatibility' }
}
function Get-PythonApplication([ValidateSet('cli','ros')][string]$Role) {
    $PythonApplications[$Role]
}
$PythonGitlink = 'external/wss-py-wrapper'
$PythonPluginPath = 'Cs_Libraries'
$PythonProjectionFiles = @($WssUniversalFiles)

function Get-PythonProjectionFiles($Record) {
    $contract = if ($Record.PSObject.Properties['universal_contract']) { [string]$Record.universal_contract } else { 'legacy-v1' }
    $expected = @(Get-WssUniversalFiles $contract)
    if ($Record.files.Count -ne $expected.Count -or @(Compare-Object $expected @($Record.files.source) -CaseSensitive).Count) {
        throw 'Projection must match its declared exact universal contract; macOS backend files cannot be omitted.'
    }
    $expected
}
function Get-PythonProducerContract([string]$Commit) {
    Assert-PythonSha $Commit
    $content = Invoke-PythonGh -Arguments @('api',"repos/cwru-non-academic/WSSCore/contents/tools/ArtifactBuild/manifests/universal.json?ref=$Commit") | ConvertFrom-Json
    if ($content.encoding -cne 'base64') { throw 'Unexpected producer manifest encoding.' }
    $manifest = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($content.content)) | ConvertFrom-Json
    Get-WssUniversalContract @($manifest.files)
}

function Invoke-PythonGh([string[]]$Arguments) {
    . "$PSScriptRoot/wss-ci/Process.ps1"
    Invoke-WssCiProcess -Executable gh -Arguments $Arguments -FailureMessage 'GitHub operation failed'
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
    $expected = @(Get-PythonProjectionFiles $Record)
    $actual = @(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/') })
    if ($actual.Count -ne $expected.Count -or @(Compare-Object $expected $actual -CaseSensitive).Count -ne 0) { throw 'Exact full universal inventory required; no fallback/extra files.' }
    foreach ($item in $Record.files) {
        if ((Get-FileHash -LiteralPath (Join-Path $Root $item.source)).Hash.ToLowerInvariant() -cne $item.sha256) { throw "Payload hash mismatch: $($item.source)" }
    }
    if ((Get-PythonProjectionDigest $Record.files) -cne $Record.projection_sha256) { throw 'Payload digest mismatch.' }
}
function New-PythonProjection([string]$ArtifactRoot, [string]$WrapperRoot, [string]$Destination, $Candidate) {
    Assert-PythonCandidate $Candidate
    if (Test-Path -LiteralPath $Destination) { throw 'Payload destination must be new.' }
    $inventory = @(Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($ArtifactRoot,$_.FullName).Replace('\','/') })
    $contract = Get-WssUniversalContract $inventory
    $expected = @(Get-WssUniversalFiles $contract)
    New-Item -ItemType Directory -Path $Destination | Out-Null
    $files = @()
    foreach ($source in $expected) {
        $target = Join-Path $Destination $source
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $ArtifactRoot $source) -Destination $target
        $files += [ordered]@{ source=$source; sha256=(Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() }
    }
    $record = [pscustomobject][ordered]@{ schema='wss-python-projection/v1'; universal_contract=$contract; candidate=$Candidate; projection_sha256=(Get-PythonProjectionDigest $files); files=$files }
    Assert-PythonProjection $Destination $record
    $record
}
function Read-PythonConfig([string]$Path,[string]$Channel='') {
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($config.schema -cne 'wss-python-ci/v1' -or $config.branch -cne 'dev' -or $config.automated_execution -cne 'pythonnet' -or
        $config.python_version -cne '3.12' -or $config.pythonnet_version -cne '3.0.5' -or
        $config.fixture_repository -cne 'cwru-non-academic/CSharp_WSS_Integration_Lib' -or $config.dotnet_expected_cases.Count -ne 16) { throw 'Unexpected Python CI contract.' }
    Assert-PythonSha $config.fixture_commit
    if ($config.fixture_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Missing fixture digest.' }
    # Ordinary committed-payload validation remains compatible with historical
    # records. Only new rollout authorization requires the explicit channel.
    if($Channel){
        . "$PSScriptRoot/wss-ci/Channel.ps1"
        $context=Get-WssCiChannelContext $Channel
        if($context.channel -ceq 'main' -and (!$config.PSObject.Properties['channels'] -or
          @(Compare-Object @('dev','main') @($config.channels) -CaseSensitive).Count -ne 0 -or $config.channels.Count -ne 2)){throw 'Main rollout requires the deployed dual-channel configuration.'}
    }
    $config
}
function Assert-PythonResults([string]$Path, $Config, [switch]$DotNet, [ValidateSet('single','multi')][string]$Stage='single') {
    # Disable DTD/entity resolution: results may originate from proposed source.
    $settings = [Xml.XmlReaderSettings]::new(); $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit; $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path,$settings)
    try { $xml=[Xml.XmlDocument]::new(); $xml.XmlResolver=$null; $xml.Load($reader) } finally { $reader.Dispose() }
    $run=$xml.DocumentElement; $cases=@($xml.SelectNodes('//test-case'))
    if ($run.get_Name() -cne 'test-run' -or $run.GetAttribute('result') -cne 'Passed' -or
        $run.GetAttribute('testcasecount') -cne '16' -or $run.GetAttribute('total') -cne '16' -or
        $run.GetAttribute('passed') -cne '16' -or $cases.Count -ne 16) { throw 'All sixteen canonical cases must be discovered, executed and passed.' }
    foreach ($attribute in @('failed','skipped','inconclusive')) { if ($run.GetAttribute($attribute) -cne '0') { throw "Nonzero or absent $attribute count." } }
    $expected=if ($DotNet) { @($Config.dotnet_expected_cases) } else { @($Config.expected_cases) }
    if ($Stage -ceq 'multi') { $expected=@($expected | Select-Object -First 10)+@($Config.multidevice_expected_cases) }
    if ($expected.Count -ne 16 -or @(Compare-Object $expected @($cases | ForEach-Object { $_.GetAttribute('name') }) -CaseSensitive).Count -ne 0 -or
        @($cases | Where-Object { $_.GetAttribute('result') -cne 'Passed' }).Count -gt 0) { throw 'Missing/duplicate/unexpected/unsuccessful canonical cases.' }
}
function Assert-PythonSource([string]$Root,[string]$Sha,[switch]$IgnoreSubmodule) {
    Assert-PythonSha $Sha
    if ((Invoke-PythonGit $Root @('rev-parse','HEAD')).Trim() -cne $Sha) { throw 'Checked-out source differs from the pinned SHA.' }
    $statusArguments=@('status','--porcelain','--untracked-files=normal')
    if ($IgnoreSubmodule) { $statusArguments+='--ignore-submodules=all' }
    if (@(Invoke-PythonGit $Root $statusArguments).Count -ne 0) { throw 'Source checkout must be clean before staging the disposable harness.' }
}
function Get-PythonAllowedWrapperPaths($Record=$null) {
    $files = if ($null -ne $Record) { @(Get-PythonProjectionFiles $Record) } else { @($WssMacOSUniversalFiles) }
    @($files | ForEach-Object { "$PythonPluginPath/$_" }) + @('.github/python-candidate.json')
}
function Assert-PythonDiff([string[]]$Paths,[string[]]$Allowed) {
    if ($Paths.Count -eq 0 -or @($Paths | Where-Object { $_ -cnotin $Allowed }).Count -gt 0) { throw 'Empty or out-of-scope promotion diff.' }
}

# Require independently enumerated single- and multi-device runtime evidence.
function Assert-PythonMultiStageEvidence([string]$Root,$Single,$Config) {
    if ($Single.stage -cne 'single') { throw 'Root evidence must identify the single stage.' }
    $multiRoot = Join-Path $Root 'multi'
    foreach ($name in @('evidence.json','results.xml','dotnet.log','projection.json')) {
        if (!(Test-Path -LiteralPath (Join-Path $multiRoot $name) -PathType Leaf)) { throw "Missing multi-stage evidence: $name" }
    }
    $multi = Get-Content (Join-Path $multiRoot 'evidence.json') -Raw | ConvertFrom-Json
    Assert-PythonSameCandidate $multi.candidate $Single.candidate
    foreach ($field in @('schema','execution','role','mode','wrapper_sha','cli_sha','fixture_sha','fixture_sha256','sdk','target_framework','test_framework','run_repository','run_id','run_sha','projection_sha256','python','pythonnet','python_executed')) {
        if ($multi.$field -cne $Single.$field) { throw "Multi-stage evidence differs: $field" }
    }
    if ($multi.stage -cne 'multi' -or $multi.discovered -ne 16 -or $multi.executed -ne 16 -or $multi.passed -ne 16 -or
        $multi.failed -ne 0 -or $multi.skipped -ne 0 -or $multi.assertion_expressions -ne 20) { throw 'Incomplete multi-stage runtime evidence.' }
    foreach ($pair in @(@('results.xml','results_sha256'),@('dotnet.log','log_sha256'))) {
        if ((Get-FileHash -LiteralPath (Join-Path $multiRoot $pair[0])).Hash.ToLowerInvariant() -cne $multi.($pair[1])) { throw 'Multi-stage content hash mismatch.' }
    }
    if ((Get-FileHash -LiteralPath (Join-Path $multiRoot 'projection.json')).Hash -cne (Get-FileHash -LiteralPath (Join-Path $Root 'projection.json')).Hash) { throw 'Multi-stage package projection differs.' }
    Assert-PythonResults (Join-Path $multiRoot 'results.xml') $Config -DotNet -Stage multi
}
