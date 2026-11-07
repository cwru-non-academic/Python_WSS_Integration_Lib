# Local/hosted regression fixture only. Never publish this synthetic product commit.
param([Parameter(Mandatory)][string]$ToolsRoot,[Parameter(Mandatory)][string]$ProductRoot,[Parameter(Mandatory)][string]$ProductSha)
$ErrorActionPreference='Stop'
function Invoke-ProfileFixtureGit([string]$Root,[string[]]$Arguments){$result=& git -C $Root @Arguments;if($LASTEXITCODE -ne 0){throw 'Proof fixture Invoke-ProfileFixtureGit operation failed.'};$result}
$ToolsRoot=[IO.Path]::GetFullPath($ToolsRoot);$ProductRoot=[IO.Path]::GetFullPath($ProductRoot)
if((Invoke-ProfileFixtureGit $ProductRoot @('rev-parse','HEAD')).Trim() -cne $ProductSha){throw 'Wrong original product source.'}
if(@(Invoke-ProfileFixtureGit $ProductRoot @('status','--porcelain','--untracked-files=all')).Count){throw 'Original product must be clean.'}
$toolSha=(Invoke-ProfileFixtureGit $ToolsRoot @('rev-parse','HEAD')).Trim()
$paths=@('.github/scripts','.github/python-ci.json','.github/dev-propagation.json','.github/main-propagation.json')
$null=Invoke-ProfileFixtureGit $ProductRoot @('fetch','--no-tags',$ToolsRoot,$toolSha)
$null=Invoke-ProfileFixtureGit $ProductRoot (@('restore','--source',$toolSha,'--staged','--worktree','--')+$paths)
$null=Invoke-ProfileFixtureGit $ProductRoot @('-c','user.name=Ordinary profile fixture','-c','user.email=profile-fixture@example.invalid','commit','--allow-empty','-m','Unpublished ordinary profile tooling fixture')
foreach($path in $paths){if((Invoke-ProfileFixtureGit $ProductRoot @('rev-parse',"HEAD:$path")) -cne (Invoke-ProfileFixtureGit $ToolsRoot @('rev-parse',"HEAD:$path"))){throw 'Profile fixture tooling/config is not identical.'}}
$changed=@(Invoke-ProfileFixtureGit $ProductRoot @('diff','--name-only',$ProductSha,'HEAD'))
foreach($path in $changed){if($path -notlike '.github/scripts/*' -and $path -cnotin $paths){throw "Product content changed: $path"}}
$null=Invoke-ProfileFixtureGit $ProductRoot @('diff','--exit-code',$ProductSha,'HEAD','--','src','Cs_Libraries','.github/python-candidate.json','conformance','pyproject.toml')
Write-Output 'PASS: identical tooling/config, unchanged real product source, payload and provenance.'
