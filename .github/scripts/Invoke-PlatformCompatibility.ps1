param(
    [Parameter(Mandatory)][string]$WrapperRoot,
    [Parameter(Mandatory)][string]$WrapperSha,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$CliRoot='',
    [string]$CliSha='',
    [string]$PythonExe='python'
)
. "$PSScriptRoot/PythonContract.ps1"
$config = Read-PythonConfig (Join-Path $WrapperRoot '.github/python-ci.json')
Assert-PythonSource $WrapperRoot $WrapperSha
Assert-PythonSource $FixtureRoot $config.fixture_commit
if ($CliRoot) { Assert-PythonSource $CliRoot $CliSha -IgnoreSubmodule }
$projection = Get-Content (Join-Path $WrapperRoot '.github/python-candidate.json') -Raw | ConvertFrom-Json
$payload = Join-Path $WrapperRoot $PythonPluginPath
Assert-PythonProjection $payload $projection
if (Test-Path -LiteralPath $OutputRoot) { throw 'Platform output must be new.' }
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
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
$options = @('--payload',$stagedPayload,'--installed',$installed)
if ($CliRoot) { $options += '--cli' }
Push-Location $OutputRoot
try {
    & $PythonExe (Join-Path $PSScriptRoot '../../conformance/platform_smoke.py') @options
    if ($LASTEXITCODE -ne 0) { throw 'Installed Python platform smoke failed.' }
} finally { Pop-Location }
# Run the identical C# platform tests against the payload consumed by Python.
# These test real backend/dependency/native loading, not emulator semantics.
$env:WSS_ARTIFACT_DIR = $stagedPayload
$env:WSS_BLE_ARTIFACT_DIR = $stagedPayload
$project = Join-Path $FixtureRoot 'tests/Wss.CSharpImplementation.Tests/Wss.CSharpImplementation.Tests.csproj'
@{sdk=@{version=$config.dotnet_sdk;rollForward='disable'}} | ConvertTo-Json | Set-Content (Join-Path $OutputRoot 'global.json')
Push-Location $OutputRoot
try {
    & dotnet test $project -c Release --filter 'FullyQualifiedName~SerialRuntimeSelectionTests|FullyQualifiedName~BleBackendLoadingTests' --logger 'trx;LogFileName=platform.trx' --results-directory $OutputRoot -p:TreatWarningsAsErrors=true
    if ($LASTEXITCODE -ne 0) { throw 'Shared C# platform compatibility tests failed.' }
} finally { Pop-Location }
& (Join-Path $FixtureRoot '.github/scripts/Verify-WssOutput.ps1') -ArtifactRoot $stagedPayload -OutputRoot (Join-Path $FixtureRoot 'tests/Wss.CSharpImplementation.Tests/bin/Release/net9.0')
if (!$?) { throw 'Platform build payload propagation failed.' }
Assert-PythonProjection $stagedPayload $projection
Assert-PythonProjection $payload $projection
Assert-PythonSource $WrapperRoot $WrapperSha
if ($CliRoot) { Assert-PythonSource $CliRoot $CliSha -IgnoreSubmodule }
if ($IsMacOS) { Write-Output 'SKIP: macOS BLE backend is not implemented; shared NUnit result records the skip.' }
@{schema='wss-python-platform/v1'; wrapper_sha=$WrapperSha; cli_sha=$CliSha; fixture_sha=$config.fixture_commit; os=[Runtime.InteropServices.RuntimeInformation]::OSDescription; projection_sha256=$projection.projection_sha256; installed_python_smoke='passed'; ble= $(if ($IsMacOS) {'skipped: backend not implemented'} else {'loading passed; no physical device tested'})} | ConvertTo-Json | Set-Content (Join-Path $OutputRoot 'platform.json')
