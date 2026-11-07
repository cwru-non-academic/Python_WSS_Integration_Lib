$ErrorActionPreference='Stop'
. "$PSScriptRoot/../PythonContract.ps1"
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$temp=Join-Path ((& python -c 'import pathlib,tempfile; print(pathlib.Path(tempfile.gettempdir()).resolve())').Trim()) ('python-test-selection-'+[guid]::NewGuid().ToString('N'))
$product=Join-Path $temp 'product'; $selected=Join-Path $temp 'selected'
$null=New-Item -ItemType Directory -Path (Join-Path $product '.github'),(Join-Path $selected 'conformance'),(Join-Path $selected '.github') -Force
$config=Join-Path $product '.github/python-ci.json'
Copy-Item (Join-Path $repository '.github/python-ci.json') $config
Copy-Item (Join-Path $repository 'conformance/test-contract.json') (Join-Path $selected 'conformance/test-contract.json')
# A selected checkout's product config is deliberately invalid and must not be consulted.
'{"baseline_ready":false,"automated_execution":"fake"}' | Set-Content (Join-Path $selected '.github/python-ci.json')
$conformance=Join-Path $selected 'conformance/test-contract.json'
foreach ($root in @($product,$selected)) {
    $null=Invoke-PythonGit $root @('init','--quiet')
    $null=Invoke-PythonGit $root @('add','.')
    $null=Invoke-PythonGit $root @('-c','user.name=Test','-c','user.email=test@example.invalid','commit','--quiet','-m','Fixture')
}
$sha=(Invoke-PythonGit $selected @('rev-parse','HEAD')).Trim()
$productSha=(Invoke-PythonGit $product @('rev-parse','HEAD')).Trim()
$arguments=@($product,$productSha,$config,$selected,$sha,$PythonWrapperRepository,('a'*64))
$valid=Resolve-PythonTestSource @arguments
if ($valid.sha -cne $sha -or $valid.contract.schema -cne 'wss-python-tests/v1') { throw 'Explicit selected contract was not loaded.' }
$default=Resolve-PythonTestSource $product $productSha $config
if ($default.sha -cne $productSha -or $default.selection_id) { throw 'Default product source changed.' }
function Reject([string]$Name,[scriptblock]$Action) {
    $rejected=$false
    try { & $Action | Out-Null } catch { $rejected=$true }
    if (!$rejected) { throw "Unsafe selection accepted: $Name" }
}
Reject 'mutable SHA' { Resolve-PythonTestSource $product $productSha $config $selected 'dev' $PythonWrapperRepository ('a'*64) }
Reject 'swapped checkout' { Resolve-PythonTestSource $product $productSha $config $product $sha $PythonWrapperRepository ('a'*64) }
Reject 'wrong SHA' { Resolve-PythonTestSource $product $productSha $config $selected ('f'*40) $PythonWrapperRepository ('a'*64) }
foreach ($index in 3..6) {
    $partial=@($arguments); $partial[$index]=''
    Reject "missing field $index" { Resolve-PythonTestSource @partial }
}
Reject 'product config from selection' { Resolve-PythonTestSource $product $productSha (Join-Path $selected '.github/python-ci.json') $selected $sha $PythonWrapperRepository ('a'*64) }
Add-Content $conformance ' '
Reject 'dirty selected contract' { Resolve-PythonTestSource @arguments }
$null=Invoke-PythonGit $selected @('restore','conformance/test-contract.json')
'rogue' | Set-Content (Join-Path $selected 'conformance/untracked.py')
Reject 'untracked selected adapter' { Resolve-PythonTestSource @arguments }
Remove-Item -LiteralPath (Join-Path $selected 'conformance/untracked.py')
$changed=Get-Content $conformance -Raw | ConvertFrom-Json
$changed | Add-Member -NotePropertyName baseline_ready -NotePropertyValue $true
$changed | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $temp 'confused.json')
Reject 'product fields in test contract' { Read-PythonTestContract (Join-Path $temp 'confused.json') }
$changed.PSObject.Properties.Remove('baseline_ready')
$changed.dotnet_expected_cases=@($changed.dotnet_expected_cases | Select-Object -First 15)
$changed | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $temp 'weakened.json')
Reject 'weakened selected inventory' { Read-PythonTestContract (Join-Path $temp 'weakened.json') }
$own=Get-Content $config -Raw | ConvertFrom-Json
$own.baseline_ready=$false
$own | ConvertTo-Json -Depth 8 | Set-Content $config
Reject 'product readiness opt-out' { Resolve-PythonTestSource @arguments }
$null=Invoke-PythonGit $product @('restore','.github/python-ci.json')
$single=[pscustomobject]@{wrapper_sha=$productSha;test_root=$valid.root;test_sha=$sha;test_repository=$valid.repository;test_selection_id=$valid.selection_id;test_contract_sha256=$valid.contract_sha256}
Assert-PythonTestEvidencePair $single $single
foreach ($field in @('test_root','test_sha','test_repository','test_selection_id','test_contract_sha256')) {
    $multi=$single | ConvertTo-Json | ConvertFrom-Json
    $multi.$field='wrong'
    Reject "stage mismatch $field" { Assert-PythonTestEvidencePair $single $multi }
    $multi=$single | ConvertTo-Json | ConvertFrom-Json
    $multi.PSObject.Properties.Remove($field)
    Reject "missing evidence $field" { Assert-PythonTestEvidencePair $single $multi }
}
Write-Output 'PASS: independent selected/default sources, immutable clean selection, complete metadata, product/test config isolation, readiness, canonical inventory, and stage binding.'
