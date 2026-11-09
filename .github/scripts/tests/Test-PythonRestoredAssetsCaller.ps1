$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$caller=Join-Path $root '.github/scripts/Invoke-PlatformCompatibility.ps1'
$source=Get-Content -LiteralPath $caller -Raw
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($caller,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Platform caller must parse.'}
$verifiers=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.Extent.Text.StartsWith('& (Join-Path') -and $n.Extent.Text.Contains('Verify-WssOutput.ps1')},$true))
if($verifiers.Count -ne 3){throw 'Shared verifier must protect the complete immutable baseline before smoke.'}
$expected="& (Join-Path `$PSScriptRoot 'wss-ci/restored-assets/Verify-WssOutput.ps1') -ArtifactRoot `$stagedPayload -OutputRoot `$builtPayload -ProjectAssetsFile `$projectAssetsFile -ProjectPath `$project -RestoreProof `$restoreProof"
if(@($verifiers | Where-Object {$_.Extent.Text -cne $expected}).Count){throw 'Verifier must use bootstrap tooling and bind exact artifact/output/project/assets inputs.'}
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
# Exercise the actual caller boundary with synthetic restore/build outputs and a
# selectable child stand-in. The Core proof and existing parent inventory are real.
$start=$source.IndexOf('# Restore and build the authenticated fixture')
$end=$source.IndexOf('# Recheck immutable sources and emit captured baseline evidence.',$start)
if($start -lt 0 -or $end -le $start){throw 'Missing bounded platform execution block.'}
$boundary=$source.Substring($start,$end-$start)
if(!$source.Substring($end).Contains('Assert-PythonSource $FixtureRoot $tests.contract.fixture_commit')){throw 'Final immutable fixture check missing.'}
$restore=$boundary.IndexOf('& dotnet restore ')
$capture=$boundary.IndexOf('$restoreProof = New-WssRestoredAssetsProof ')
$build=$boundary.IndexOf('& dotnet build ')
$smoke=$boundary.IndexOf('& $PythonExe (Join-Path $tests.root')
$test=$boundary.IndexOf('& dotnet test ')
if(!($restore -ge 0 -and $restore -lt $capture -and $capture -lt $build -and $build -lt $test -and $test -lt $smoke)){throw 'Trusted restore/proof/build/test must precede selected child.'}
if(!$boundary.Contains('--artifacts-path $buildRoot --no-restore -p:TreatWarningsAsErrors=true') -or !$boundary.Contains('--artifacts-path $buildRoot --no-restore --no-build')){throw 'Build/test may not implicitly restore or rebuild.'}
if(@([regex]::Matches($boundary,'-p:ImportDirectoryBuildProps=false -p:ImportDirectoryBuildTargets=false')).Count -ne 3){throw 'Restore, build and test must disable ambient Directory.Build imports.'}
$global:WssPythonRestoredTestcount=0
function Assert-PythonSource {} # Existing immutable source checks are asserted above.
function Assert-PythonToolingBinding {}
function Assert-PythonProjection {}
function Get-PythonProjectionFiles {$global:WssPythonRestoredTestfiles}
function Write-FixtureBytes([string]$Path,[string]$Value){$null=New-Item -ItemType Directory (Split-Path $Path) -Force;[IO.File]::WriteAllText($Path,$Value)}
function dotnet {
    $global:WssPythonRestoredTesttrace.Add([string]$args[0])
    $global:LASTEXITCODE=0
    if(($args -join '|') -cnotmatch '(?:^|\|)-p:\|?DisablePackageAssetsCache=true(?:\||$)'){throw ('SDK package cache must be disabled consistently: '+($args -join '|'))}
    if($global:WssPythonRestoredTesttrace.Contains('smoke')){throw 'Project reevaluation occurred after selected smoke.'}
    if($args[0] -ceq 'restore'){
        $asset='lib/net8.0/System.IO.Ports.dll'
        Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestcache 'system.io.ports/8.0.0/.nupkg.metadata') '{}'
        Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestcache "system.io.ports/8.0.0/$asset") 'neutral bytes'
        $value=@{version=3;targets=@{'net9.0'=@{'System.IO.Ports/8.0.0'=@{type='package';runtime=@{$asset=@{}}}}};libraries=@{'System.IO.Ports/8.0.0'=@{type='package';path='system.io.ports/8.0.0';files=@($asset)}};packageFolders=@{$global:WssPythonRestoredTestcache=@{}};project=@{restore=@{projectPath=$global:WssPythonRestoredTestproject}}}
        Write-FixtureBytes $global:WssPythonRestoredTestassets ($value|ConvertTo-Json -Depth 20)
    } elseif($args[0] -ceq 'build'){
        if($args -cnotcontains '--no-restore'){throw 'Synthetic build requires no restore.'}
        $null=New-Item -ItemType Directory $global:WssPythonRestoredTestbuilt -Force
        Copy-Item -Path (Join-Path $global:WssPythonRestoredTestpayload '*') -Destination $global:WssPythonRestoredTestbuilt -Recurse
        Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestbuilt 'System.IO.Ports.dll') 'neutral bytes'
        Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestbuilt 'Wss.CSharpImplementation.Tests.dll') 'synthetic test assembly, never loaded'
        Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestbuilt 'testhost.dll') 'synthetic runner, never loaded'
    } elseif($args[0] -ceq 'test'){
        Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestoutput 'platform.trx') '<TestRun><Results><UnitTestResult testName="FacadeLoadsCurrentPlatformBackendAndDependencies" outcome="Passed" /></Results></TestRun>'
        if($args -cnotcontains '--no-restore' -or $args -cnotcontains '--no-build'){throw 'Synthetic test cannot restore/build.'}
        if($global:WssPythonRestoredTestmutation -ceq 'after-test-assets'){Add-Content -LiteralPath $global:WssPythonRestoredTestassets -Value ' '}
    } else {throw 'Unexpected dotnet invocation.'}
}
function Invoke-SyntheticSmoke {
    $global:WssPythonRestoredTesttrace.Add('smoke')
    if($restoreProof -isnot [Wss.BuildTools.RestoredAssetProof]){throw 'Smoke executed before parent proof capture.'}
    switch($global:WssPythonRestoredTestmutation){
        'assets'{Add-Content -LiteralPath $global:WssPythonRestoredTestassets -Value ' '}
        'project'{Add-Content -LiteralPath $global:WssPythonRestoredTestproject -Value '<!-- changed -->'}
        'neutral'{Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestcache 'system.io.ports/8.0.0/lib/net8.0/System.IO.Ports.dll') 'changed neutral'}
        'test-output'{Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestbuilt 'Wss.CSharpImplementation.Tests.dll') 'changed tests'}
        'runner-output'{Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestbuilt 'testhost.dll') 'changed runner'}
        'addition'{Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestbuilt 'unexpected.dll') 'unexpected'}
        'deletion'{Remove-Item -LiteralPath (Join-Path $global:WssPythonRestoredTestbuilt 'testhost.dll')}
        'generated-config'{Write-FixtureBytes (Join-Path (Split-Path $global:WssPythonRestoredTestassets) 'injected.targets') '<Project />'}
        'redirected-output'{
            $destination=Join-Path $global:WssPythonRestoredTestbuilt 'redirected'
            $kind=if($IsWindows){'Junction'}else{'SymbolicLink'}
            $null=New-Item -ItemType $kind -Path $destination -Target $global:WssPythonRestoredTestcache
        }
        'trx'{Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestoutput 'platform.trx') '<changed />'}
        'installed-product'{Write-FixtureBytes (Join-Path (Split-Path $global:WssPythonRestoredTestpayload) 'product.py') 'changed product'}
        'package-import'{Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestcache 'system.io.ports/8.0.0/build/injected.props') '<Project><Target Name="Injected" /></Project>'}
        'sdk'{Add-Content -LiteralPath (Join-Path $global:WssPythonRestoredTestoutput 'global.json') -Value ' '}
    }
    Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestoutput 'python-smoke.json') '{"architecture":"x64","execution":"native","ble":"passed: synthetic","macos_ble_declared":false}'
    $global:LASTEXITCODE=0
}
$tempParent=[IO.Path]::GetTempPath()
if(!$IsWindows){Push-Location $tempParent;try{$tempParent=(& /bin/pwd -P).Trim()}finally{Pop-Location}}
$temp=Join-Path $tempParent ('python-restored-caller-'+[guid]::NewGuid().ToString('N'))
$tools=Join-Path $temp 'tools'
$null=New-Item -ItemType Directory (Join-Path $tools 'wss-ci') -Force
Copy-Item -LiteralPath (Join-Path $root '.github/scripts/wss-ci/restored-assets') -Destination (Join-Path $tools 'wss-ci/restored-assets') -Recurse
Copy-Item -LiteralPath (Join-Path $root '.github/scripts/SelectedParentSnapshot.ps1') -Destination $tools
$runner=Join-Path $tools 'Invoke-Boundary.ps1'
Set-Content -LiteralPath $runner -Value ('param($FixtureRoot,$OutputRoot,$stagedPayload,$config,$tests,$projection,$PythonExe,$CliRoot,$toolBinding)
$installed=Split-Path $stagedPayload; $contract=''legacy-v1'''+"`n"+$boundary)
try {
    foreach($fixture in @('02172a64c55becd5535204f46f10b4755bf3ee05','fc427c5b8bc6534a7d02f00283830072572aa03a')){
        foreach($global:WssPythonRestoredTestmutation in @('none','assets','project','neutral','test-output','runner-output','addition','deletion','generated-config','redirected-output','sdk','trx','installed-product','package-import','after-test-assets')){
            $case=Join-Path $temp "$fixture/$global:WssPythonRestoredTestmutation"
            $fixtureRoot=Join-Path $case 'fixture';$global:WssPythonRestoredTestoutput=Join-Path $case 'output'
            $global:WssPythonRestoredTestproject=Join-Path $fixtureRoot 'tests/Wss.CSharpImplementation.Tests/Wss.CSharpImplementation.Tests.csproj'
            $global:WssPythonRestoredTestassets=Join-Path $global:WssPythonRestoredTestoutput 'shared-build/obj/Wss.CSharpImplementation.Tests/project.assets.json'
            $global:WssPythonRestoredTestbuilt=Join-Path $global:WssPythonRestoredTestoutput 'shared-build/bin/Wss.CSharpImplementation.Tests/release'
            $global:WssPythonRestoredTestcache=Join-Path $case 'custom cache';$global:WssPythonRestoredTestpayload=Join-Path $case 'installed/Cs_Libraries'
            Write-FixtureBytes $global:WssPythonRestoredTestproject '<Project />'
            $null=New-Item -ItemType Directory $global:WssPythonRestoredTestoutput -Force
            . (Join-Path $tools 'wss-ci/restored-assets/Universal-WssFiles.ps1')
            $global:WssPythonRestoredTestfiles=$WssUniversalFiles
            Write-FixtureBytes (Join-Path (Split-Path $global:WssPythonRestoredTestpayload) 'product.py') 'original product'
            foreach($relative in $WssUniversalFiles){Write-FixtureBytes (Join-Path $global:WssPythonRestoredTestpayload $relative) "fixture $relative"}
            $global:WssPythonRestoredTesttrace=[Collections.Generic.List[string]]::new();$failure=$null
            try {& $runner $fixtureRoot $global:WssPythonRestoredTestoutput $global:WssPythonRestoredTestpayload @{dotnet_sdk='9.0.316'} @{root='selected';contract=@{fixture_commit=$fixture}} @{} 'Invoke-SyntheticSmoke' '' $null | Out-Null}catch{$failure=$_}
            if($global:WssPythonRestoredTestmutation -cin @('none','package-import')){
                if($failure){throw $failure}
                if(($global:WssPythonRestoredTesttrace -join ',') -cne 'restore,build,test,smoke'){throw 'Unexpected actual caller execution order.'}
            } else {
                if(!$failure){throw "Mutation accepted: $global:WssPythonRestoredTestmutation"}
                $expectedTrace=if($global:WssPythonRestoredTestmutation -ceq 'after-test-assets'){'restore,build,test'}else{'restore,build,test,smoke'}
                if(($global:WssPythonRestoredTesttrace -join ',') -cne $expectedTrace){throw 'Mutation case failed before its intended child boundary.'}
                if($failure.Exception.Message -notmatch 'changed|mismatch|proof|inventory|captured|redirected'){throw "Unexpected mutation failure: $failure"}
            }
            $global:WssPythonRestoredTestcount++
        }
    }
} finally {
    $resolved=[IO.Path]::GetFullPath($temp)
    $parent=[IO.Path]::GetFullPath($tempParent).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if((Split-Path -Parent $resolved) -cne $parent -or (Split-Path -Leaf $resolved) -cnotmatch '^python-restored-caller-[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup path.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
"PASS: $global:WssPythonRestoredTestcount real caller ordering/mutation cases; synthetic bytes only, no WSS/native execution."
$profile=Get-Content -LiteralPath (Join-Path $root '.github/scripts/PythonProfiles/Contract.ps1') -Raw
$workflow=Get-Content -LiteralPath (Join-Path $root '.github/workflows/ordinary-profile-proof.yml') -Raw
foreach($sha in @('02172a64c55becd5535204f46f10b4755bf3ee05','fc427c5b8bc6534a7d02f00283830072572aa03a')){if(!$profile.Contains($sha) -or !$workflow.Contains($sha)){throw 'Both immutable fixture profiles must remain covered.'}}
if(!$workflow.Contains('./tools/.github/scripts/Invoke-PlatformCompatibility.ps1') -or !$workflow.Contains('-ToolsRoot $tools -ToolsSha $toolSha -ConfigPath')){throw 'Ordinary proof must explicitly adopt bootstrap tooling.'}
'PASS: shared verifier caller captures both immutable fixtures; exact restore inputs and existing authority/platform gates retained.'
