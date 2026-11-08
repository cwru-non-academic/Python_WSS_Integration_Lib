$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$caller=Join-Path $root '.github/scripts/Invoke-PlatformCompatibility.ps1'
$source=Get-Content -LiteralPath $caller -Raw
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($caller,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Platform caller must parse.'}
$verifiers=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.Extent.Text.StartsWith('& (Join-Path') -and $n.Extent.Text.Contains('Verify-WssOutput.ps1')},$true))
if($verifiers.Count -ne 1){throw 'Exactly one shared verifier call is required.'}
$expected="& (Join-Path `$PSScriptRoot 'wss-ci/restored-assets/Verify-WssOutput.ps1') -ArtifactRoot `$stagedPayload -OutputRoot `$builtPayload -ProjectAssetsFile `$projectAssetsFile -ProjectPath `$project"
if($verifiers[0].Extent.Text -cne $expected){throw 'Verifier must use bootstrap tooling and bind exact artifact/output/project/assets inputs.'}
foreach($required in @(
    "`$projectAssetsFile = Join-Path `$buildRoot 'obj/Wss.CSharpImplementation.Tests/project.assets.json'",
    "`$project = Join-Path `$FixtureRoot 'tests/Wss.CSharpImplementation.Tests/Wss.CSharpImplementation.Tests.csproj'",
    '& dotnet test $project -c Release --artifacts-path $buildRoot',
    'Assert-PythonSource $FixtureRoot $tests.contract.fixture_commit',
    'Resolve-PythonOrdinaryTooling -ToolsRoot $ToolsRoot -ToolsSha $ToolsSha -ConfigPath $ConfigPath',
    'if($toolBinding){Assert-PythonToolingBinding $ToolsRoot $ToolsSha $ConfigPath}',
    'FullyQualifiedName~SerialRuntimeSelectionTests|FullyQualifiedName~BleBackendLoadingTests',
    'Declared macOS BLE activation must pass.',
    'The pinned shared C# fixture must execute macOS BLE; a skipped legacy fixture is not acceptance.',
    'Shared platform build dropped or changed a declared asset:',
    'Assert-PythonProfileTestSource $tests',
    'Platform output must remain outside every immutable source.'
)) {if(!$source.Contains($required)){throw "Required platform authority or gate missing: $required"}}
if($source.Contains("Join-Path `$FixtureRoot '.github/scripts/Verify-WssOutput.ps1'")){throw 'Immutable fixture tooling must not select package assets.'}
# Only evaluate the caller's path assignments and verifier command, with a
# capture-only script in a fresh temporary checkout-shaped directory. No WSS
# assemblies, platform smoke, dotnet test, or selected-source machinery runs.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('python-restored-caller-'+[guid]::NewGuid().ToString('N'))
$stubRoot=Join-Path $temp 'tools/.github/scripts'
$stub=Join-Path $stubRoot 'wss-ci/restored-assets/Verify-WssOutput.ps1'
$null=New-Item -ItemType Directory -Path (Split-Path $stub) -Force
try {
    Set-Content -LiteralPath $stub -Value 'param($ArtifactRoot,$OutputRoot,$ProjectAssetsFile,$ProjectPath) [pscustomobject]@{artifact=$ArtifactRoot;output=$OutputRoot;assets=$ProjectAssetsFile;project=$ProjectPath}'
    $assignment=$ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$projectAssetsFile'},$true)
    foreach($fixture in @('02172a64c55becd5535204f46f10b4755bf3ee05','fc427c5b8bc6534a7d02f00283830072572aa03a')) {
        $runner=Join-Path $stubRoot 'Capture-Caller.ps1'
        Set-Content -LiteralPath $runner -Value ('param($buildRoot,$stagedPayload,$builtPayload,$project)'+"`n"+$assignment.Extent.Text+"`n"+$verifiers[0].Extent.Text)
        $build=Join-Path $temp "$fixture/shared-build"
        $project=Join-Path $temp "$fixture/fixture/tests/Wss.CSharpImplementation.Tests/Wss.CSharpImplementation.Tests.csproj"
        $actual=& $runner $build 'staged payload' 'built payload' $project
        if($actual.artifact -cne 'staged payload' -or $actual.output -cne 'built payload' -or $actual.project -cne $project -or $actual.assets -cne (Join-Path $build 'obj/Wss.CSharpImplementation.Tests/project.assets.json')){throw "Incorrect verifier invocation for fixture $fixture"}
    }
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if((Split-Path -Parent $resolved) -cne $parent -or (Split-Path -Leaf $resolved) -cnotmatch '^python-restored-caller-[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup path.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$profile=Get-Content -LiteralPath (Join-Path $root '.github/scripts/PythonProfiles/Contract.ps1') -Raw
$workflow=Get-Content -LiteralPath (Join-Path $root '.github/workflows/ordinary-profile-proof.yml') -Raw
foreach($sha in @('02172a64c55becd5535204f46f10b4755bf3ee05','fc427c5b8bc6534a7d02f00283830072572aa03a')){if(!$profile.Contains($sha) -or !$workflow.Contains($sha)){throw 'Both immutable fixture profiles must remain covered.'}}
if(!$workflow.Contains('./tools/.github/scripts/Invoke-PlatformCompatibility.ps1') -or !$workflow.Contains('-ToolsRoot $tools -ToolsSha $toolSha -ConfigPath')){throw 'Ordinary proof must explicitly adopt bootstrap tooling.'}
'PASS: shared verifier caller captures both immutable fixtures; exact restore inputs and existing authority/platform gates retained.'
