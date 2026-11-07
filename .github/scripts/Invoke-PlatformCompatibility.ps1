param(
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$ToolsRoot='', [string]$ToolsSha='', [string]$ConfigPath='',
    [string]$TestRoot='',
    [string]$TestSha='',
    [string]$TestRepository='',
    [string]$TestSelectionId='',
    [string]$CliRoot='',
    [string]$CliSha='',
    [string]$PythonExe='python',
    [ValidateSet('committed','candidate')][string]$Mode='committed',
    [string]$ArtifactRoot='',
    [string]$CandidatePath=''
)
. "$PSScriptRoot/PythonContract.ps1"
$toolBinding=$null
if($Mode -ceq 'committed') {
    . "$PSScriptRoot/PythonProfiles/Contract.ps1"
    if($ToolsRoot -or $ToolsSha -or $ConfigPath){
        . "$PSScriptRoot/PythonProfiles/Tooling.ps1"
        $toolBinding=Resolve-PythonOrdinaryTooling -ToolsRoot $ToolsRoot -ToolsSha $ToolsSha -ConfigPath $ConfigPath -WrapperRoot $WrapperRoot -WrapperSha $WrapperSha
        $config=$toolBinding.config
    }else{$config=Read-PythonProfileProductConfig (Join-Path $WrapperRoot '.github/python-ci.json')}
} else {
    if($ToolsRoot -or $ToolsSha -or $ConfigPath){throw 'Candidate platform validation does not accept ordinary tooling overrides.'}
    $config=Read-PythonConfig (Join-Path $WrapperRoot '.github/python-ci.json')
    $tests=Resolve-PythonTestSource $WrapperRoot $WrapperSha (Join-Path $WrapperRoot '.github/python-ci.json') $TestRoot $TestSha $TestRepository $TestSelectionId
}
Assert-PythonSource $WrapperRoot $WrapperSha
if($Mode -ceq 'committed' -and $CliRoot){Assert-PythonOrdinaryCliPair $CliRoot $CliSha $WrapperSha}

if ($CliRoot) { Assert-PythonSource $CliRoot $CliSha -IgnoreSubmodule }
if (Test-Path -LiteralPath $OutputRoot) { throw 'Platform output must be new.' }
$output=[IO.Path]::GetFullPath($OutputRoot)
foreach($source in @($WrapperRoot,$CliRoot,$FixtureRoot,$TestRoot,$ToolsRoot) | Where-Object {$_}){
    $inputRoot=[IO.Path]::GetFullPath($source)
    if($output -eq $inputRoot -or $output.StartsWith($inputRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Platform output must remain outside every immutable source.'}
}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
if ($Mode -ceq 'candidate') {
    if (!$ArtifactRoot -or !$CandidatePath) { throw 'Candidate platform checks require the exact resolved artifact; no fallback.' }
    $candidate = Get-Content -LiteralPath $CandidatePath -Raw | ConvertFrom-Json
    $payload = Join-Path $OutputRoot 'projection'
    $projection = New-PythonProjection $ArtifactRoot $WrapperRoot $payload $candidate
} else {
    if ($ArtifactRoot -or $CandidatePath) { throw 'Committed platform checks cannot accept candidate overrides.' }
    $projection = Get-Content (Join-Path $WrapperRoot '.github/python-candidate.json') -Raw | ConvertFrom-Json
    $payload = Join-Path $WrapperRoot $PythonPluginPath
    Assert-PythonProjection $payload $projection
}
if($Mode -ceq 'committed') {
    $profile=Resolve-WssReviewedProfile $payload $projection.candidate
    $profileContract=Get-PythonProfileContract $profile.profile
    $tests=Resolve-PythonProfileTests $WrapperRoot $WrapperSha $TestRoot $TestSha $TestRepository $TestSelectionId $profileContract
    $tests | Add-Member -NotePropertyName contract -NotePropertyValue $profileContract
}
Assert-PythonSource $FixtureRoot $tests.contract.fixture_commit
$contract = Get-WssUniversalContract @(Get-PythonProjectionFiles $projection)
$installed = Join-Path $OutputRoot 'installed'
$wheels = Join-Path $OutputRoot 'wheels'
# Build disposable copies so packaging never mutates the immutable source checkouts.
$packages = @(@{root=$WrapperRoot; name='wrapper'})
if ($CliRoot) { $packages += @{root=$CliRoot; name='cli'} }
foreach ($package in $packages) {
    $source = Join-Path $OutputRoot $package.name
    New-Item -ItemType Directory -Path $source | Out-Null
    foreach ($item in @('src','pyproject.toml','README.md')) {
        Copy-Item -LiteralPath (Join-Path $package.root $item) -Destination $source -Recurse
    }
    & $PythonExe -m build --wheel --outdir $wheels $source
    if ($LASTEXITCODE -ne 0) { throw "Wheel build failed: $($package.name)" }
}
$wheelFiles = @(Get-ChildItem -LiteralPath $wheels -Filter '*.whl' | ForEach-Object FullName)
& $PythonExe -m pip install --no-deps --target $installed @wheelFiles
if ($LASTEXITCODE -ne 0) { throw 'Wheel installation failed.' }
$stagedPayload = Join-Path $installed 'Cs_Libraries'
Copy-Item -LiteralPath $payload -Destination $stagedPayload -Recurse
Assert-PythonProjection $stagedPayload $projection
$env:PYTHONNET_RUNTIME = 'coreclr'
$env:PYTHONPATH = $installed
$env:PYTHONDONTWRITEBYTECODE = '1'
$smokeResult = Join-Path $OutputRoot 'python-smoke.json'
$options = @('--payload',$stagedPayload,'--installed',$installed,'--contract',$contract,'--output',$smokeResult)
if ($CliRoot) { $options += '--cli' }
Push-Location $OutputRoot
try {
    & $PythonExe (Join-Path $tests.root 'conformance/platform_smoke.py') @options
    if ($LASTEXITCODE -ne 0) { throw 'Installed Python platform smoke failed.' }
} finally { Pop-Location }
# Run the identical C# platform tests against the payload consumed by Python.
# These test real backend/dependency/native loading, not emulator semantics.
$env:WSS_ARTIFACT_DIR = $stagedPayload
$env:WSS_BLE_ARTIFACT_DIR = $stagedPayload
$project = Join-Path $FixtureRoot 'tests/Wss.CSharpImplementation.Tests/Wss.CSharpImplementation.Tests.csproj'
$buildRoot = Join-Path $OutputRoot 'shared-build'
@{sdk=@{version=$config.dotnet_sdk;rollForward='disable'}} | ConvertTo-Json | Set-Content (Join-Path $OutputRoot 'global.json')
Push-Location $OutputRoot
try {
    & dotnet test $project -c Release --artifacts-path $buildRoot --filter 'FullyQualifiedName~SerialRuntimeSelectionTests|FullyQualifiedName~BleBackendLoadingTests' --logger 'trx;LogFileName=platform.trx' --results-directory $OutputRoot -p:TreatWarningsAsErrors=true
    if ($LASTEXITCODE -ne 0) { throw 'Shared C# platform compatibility tests failed.' }
} finally { Pop-Location }
$testOutputs = @(Get-ChildItem -LiteralPath (Join-Path $buildRoot 'bin/Wss.CSharpImplementation.Tests') -Filter 'Wss.CSharpImplementation.Tests.dll' -Recurse -File)
if ($testOutputs.Count -ne 1) { throw 'Expected one isolated shared platform build output.' }
$builtPayload = $testOutputs[0].Directory.FullName
& (Join-Path $FixtureRoot '.github/scripts/Verify-WssOutput.ps1') -ArtifactRoot $stagedPayload -OutputRoot $builtPayload
if (!$?) { throw 'Platform build payload propagation failed.' }
foreach ($relative in @(Get-PythonProjectionFiles $projection)) {
    if ($relative -ceq 'System.IO.Ports.dll') { continue } # Verified NuGet runtime selection above.
    if ((Get-FileHash (Join-Path $stagedPayload $relative)).Hash -cne (Get-FileHash (Join-Path $builtPayload $relative)).Hash) {
        throw "Shared platform build dropped or changed a declared asset: $relative"
    }
}
$smoke = Get-Content $smokeResult -Raw | ConvertFrom-Json
if ($IsMacOS -and $contract -ceq 'macos-ble-v1') {
    if (!$smoke.macos_ble_declared -or !$smoke.ble.StartsWith('passed:',[StringComparison]::Ordinal)) { throw 'Declared macOS BLE activation must pass.' }
    [xml]$trx = Get-Content (Join-Path $OutputRoot 'platform.trx') -Raw
    if (@($trx.TestRun.Results.UnitTestResult | Where-Object { $_.testName -ceq 'FacadeLoadsCurrentPlatformBackendAndDependencies' -and $_.outcome -ceq 'Passed' }).Count -ne 1) {
        throw 'The pinned shared C# fixture must execute macOS BLE; a skipped legacy fixture is not acceptance.'
    }
}
if($toolBinding){Assert-PythonToolingBinding $ToolsRoot $ToolsSha $ConfigPath}
Assert-PythonProjection $stagedPayload $projection
Assert-PythonProjection $payload $projection
Assert-PythonSource $WrapperRoot $WrapperSha
if($Mode -ceq 'committed' -and $CliRoot){Assert-PythonOrdinaryCliPair $CliRoot $CliSha $WrapperSha}
if ($CliRoot) { Assert-PythonSource $CliRoot $CliSha -IgnoreSubmodule }
if($Mode -ceq 'committed'){Assert-PythonProfileTestSource $tests}else{Assert-PythonTestSource $tests}
if ($IsMacOS -and $contract -ceq 'legacy-v1') { Write-Output 'UNSUPPORTED: exact legacy payload does not declare macOS BLE; no BLE support is claimed.' }
@{tooling_root=$(if($toolBinding){$toolBinding.tooling_root}else{''});tooling_sha=$(if($toolBinding){$toolBinding.tooling_sha}else{''});tooling_config_sha256=$(if($toolBinding){$toolBinding.tooling_config_sha256}else{''});schema='wss-python-platform/v2'; mode=$Mode; candidate=$projection.candidate; wrapper_sha=$WrapperSha; cli_sha=$CliSha; fixture_sha=$tests.contract.fixture_commit; test_root=$tests.root; test_sha=$tests.sha; test_repository=$tests.repository; test_selection_id=$tests.selection_id; test_contract_sha256=$tests.contract_sha256; os=[Runtime.InteropServices.RuntimeInformation]::OSDescription; projection_sha256=$projection.projection_sha256; universal_contract=$contract; architecture=$smoke.architecture; execution=$smoke.execution; platform_trx_sha256=(Get-FileHash (Join-Path $OutputRoot 'platform.trx')).Hash.ToLowerInvariant(); installed_python_smoke='passed'; ble=$smoke.ble; python_smoke_sha256=(Get-FileHash $smokeResult).Hash.ToLowerInvariant(); run_repository=$env:GITHUB_REPOSITORY; run_id=$env:GITHUB_RUN_ID; run_sha=$env:GITHUB_SHA} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputRoot 'platform.json')
