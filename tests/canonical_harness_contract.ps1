# Source-only regression. No candidate assemblies are loaded or executed.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('python-harness-contract-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$fixtureRoot=Join-Path $temp 'fixture'
$fixtureDir=Join-Path $fixtureRoot 'tests/Wss.CSharpImplementation.Tests'
$null=New-Item -ItemType Directory -Path $fixtureDir -Force
$fixturePath=Join-Path $fixtureDir 'StimulationControllerConformanceTests.cs'
$source=[IO.File]::ReadAllText((Join-Path $root '.github/scripts/PythonProfiles/fixtures/layered-v1/StimulationControllerConformanceTests.cs'))
$canonical=$source.Replace("`r`n","`n").Replace("`n","`r`n")
[IO.File]::WriteAllText($fixturePath,$canonical)
$projection=Join-Path $temp 'projection'
$null=New-Item -ItemType Directory -Path $projection
# Staging accepts file copies only; these empty placeholders can never execute.
[IO.File]::WriteAllBytes((Join-Path $projection 'WSS_Core_Interface.dll'),[byte[]]@())
$config=Get-Content (Join-Path $root '.github/python-ci.json') -Raw | ConvertFrom-Json
if((Get-FileHash $fixturePath).Hash.ToLowerInvariant() -cne $config.fixture_sha256){throw 'Product fixture and reviewed canonical source differ.'}
$count=0
foreach($role in @('wrapper','cli')) {
 $target=Join-Path $temp $role
 & (Join-Path $root 'conformance/Prepare-Harness.ps1') -CSharpIntegrationRoot $fixtureRoot -Destination $target -ProjectionRoot $projection -Role $role -PythonRuntimeAssembly (Join-Path $temp 'not-executed.dll')
 $inputs=Get-Content (Join-Path $target 'conformance-inputs.json') -Raw | ConvertFrom-Json
 if($inputs.assertion_expressions -ne 20 -or $inputs.canonical_fixture_sha256 -cne $config.fixture_sha256){throw 'Modern harness provenance differs.'}
 $adapted=[IO.File]::ReadAllText((Join-Path $target 'StimulationControllerConformanceTests.cs'))
 $before=@([regex]::Matches($canonical,'Assert\.That\(.*?;','Singleline').Value)
 $after=@([regex]::Matches($adapted,'Assert\.That\(.*?;','Singleline').Value)
 if($before.Count -ne 20 -or ($before -join "`n") -cne ($after -join "`n")){throw 'Canonical assertions changed.'}
 $count+=2
}
$adapter=[IO.File]::ReadAllText((Join-Path $root 'conformance/PythonConformanceAdapter.cs'))
foreach($method in @('StimWithMode','LoadParamsJson','GetModelConfigCTRL')) {
 if($adapter -cnotmatch ('public [^\r\n]+ '+$method+'\(') -or $adapter -cnotmatch ('\(\(dynamic\)_controller\)\.'+$method+'\(')){throw "Missing production forwarding: $method"}
 $count++
}
foreach($variant in @('legacy','modified')) {
 $text=if($variant -ceq 'legacy'){[IO.File]::ReadAllText((Join-Path $root '.github/scripts/PythonProfiles/fixtures/legacy-v1/StimulationControllerConformanceTests.cs')).Replace("`r`n","`n").Replace("`n","`r`n")}else{$canonical.Replace('Assert.That','Assert.That /* changed */')}
 [IO.File]::WriteAllText($fixturePath,$text)
 $rejected=$false
 try { & (Join-Path $root 'conformance/Prepare-Harness.ps1') -CSharpIntegrationRoot $fixtureRoot -Destination (Join-Path $temp $variant) -ProjectionRoot $projection -PythonRuntimeAssembly (Join-Path $temp 'not-executed.dll') } catch { if($_.Exception.Message -cne 'Canonical fixture digest changed.'){throw};$rejected=$true }
 if(!$rejected){throw "Accepted incompatible $variant fixture."}
 $count++
}
. (Join-Path $root '.github/scripts/PythonProfiles/Contract.ps1')
$legacy=Get-PythonProfileContract 'legacy-v1';$modern=Get-PythonProfileContract 'layered-v1'
if($legacy.single_cases.Count -ne 10 -or $legacy.multi_cases.Count -ne 0 -or $legacy.assertion_expressions -ne 18){throw 'Ordinary legacy coverage changed.'}
if($modern.single_cases.Count -ne 16 -or $modern.multi_cases.Count -ne 16 -or $modern.assertion_expressions -ne 20){throw 'Modern mandatory coverage changed.'}
$count+=2
Write-Output "PASS: $count source-only harness/profile checks; no DLL execution. Evidence retained at $temp"
