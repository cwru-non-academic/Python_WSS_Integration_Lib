# Trusted product-side validation. Selected checkouts supply only conformance files.
# The campaign bootstrap authenticates selection_id before invoking this runner.
# A syntactically valid ID here is a binding, not proof of authorization.
function Read-PythonTestContract([string]$Path) {
    $value=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $keys=@('schema','fixture_repository','fixture_commit','fixture_sha256','dotnet_expected_cases','multidevice_expected_cases')
    if (@(Compare-Object $keys @($value.PSObject.Properties.Name) -CaseSensitive).Count -ne 0 -or $value.schema -cne 'wss-python-tests/v1') {
        throw 'Selected test contract must contain only versioned test fields; product configuration is forbidden.'
    }
    Assert-PythonSha $value.fixture_commit
    if ($value.fixture_repository -cne 'cwru-non-academic/CSharp_WSS_Integration_Lib' -or
        $value.fixture_sha256 -cne '14313786be4d5c6daea28e40d2f48567cbc1356feb0f0309e0a212339137923b') { throw 'Selected tests must preserve the canonical fixture.' }
    $single=@('AnalogStimulationThroughCSharpImplementationPassesCoreConformance','InitializationThroughCSharpImplementationPassesCoreConformance','normalized.minus-0.2','normalized.0.0','normalized.0.37','normalized.0.5','normalized.1.0','normalized.1.2','RuntimeEventEditThroughCSharpImplementationResumesConformantStreaming','StopStimulationThroughCSharpImplementationDoesNotResumeStreaming','analog.multichannel-isolation','normalized.multichannel-isolation','modeled.p.pw.single','modeled.p.pa.single','modeled.pd.pw.single','modeled.pd.pa.single')
    $multi=@('analog.multidevice-isolation','normalized.multidevice-isolation','modeled.p.pw.multi','modeled.p.pa.multi','modeled.pd.pw.multi','modeled.pd.pa.multi')
    # Ordering matters: the first ten cases are retained in the multi stage.
    if (($value.dotnet_expected_cases -join "`n") -cne ($single -join "`n") -or
        ($value.multidevice_expected_cases -join "`n") -cne ($multi -join "`n")) { throw 'Selected tests cannot weaken canonical case inventories.' }
    $value
}
function Assert-PythonTestSource($Tests) {
    Assert-PythonSource $Tests.root $Tests.sha
    $top=[IO.Path]::GetFullPath((Invoke-PythonGit $Tests.root @('rev-parse','--show-toplevel')).Trim())
    if ($top -cne $Tests.root) { throw 'TestRoot must identify the checkout root, not a nested directory.' }
    if (@(Invoke-PythonGit $Tests.root @('status','--porcelain','--untracked-files=all','--ignored','--','conformance')).Count) {
        throw 'Selected conformance source must be clean, including ignored files.'
    }
    if ($Tests.contract_sha256 -and (Get-FileHash -LiteralPath (Join-Path $Tests.root 'conformance/test-contract.json')).Hash.ToLowerInvariant() -cne $Tests.contract_sha256) { throw 'Selected test contract changed during execution.' }
}
function Resolve-PythonTestSource([string]$WrapperRoot,[string]$WrapperSha,[string]$ConfigPath,[string]$TestRoot='',[string]$TestSha='',[string]$TestRepository='',[string]$TestSelectionId='') {
    $explicit=[bool]($TestRoot -or $TestSha -or $TestRepository -or $TestSelectionId)
    $product=Read-PythonConfig $ConfigPath
    if ($explicit) {
        if (!$TestRoot -or !$TestSha -or !$TestRepository -or !$TestSelectionId) { throw 'Explicit test selection requires TestRoot, TestSha, TestRepository and TestSelectionId together.' }
        Assert-PythonSha $TestSha
        if ($TestRepository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $TestSelectionId -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid immutable test selection binding.' }
        if ([IO.Path]::GetFullPath($ConfigPath) -cne [IO.Path]::GetFullPath((Join-Path $WrapperRoot '.github/python-ci.json'))) { throw 'Product config must come from WrapperRoot, not selected tests.' }
        if ($product.baseline_ready -cne $true) { throw 'Product readiness cannot be overridden by selected tests.' }
        if ($env:GITHUB_REF -ceq 'refs/heads/main') { $null=Read-PythonConfig $ConfigPath 'main' }
    } else {
        $TestRoot=$WrapperRoot; $TestSha=$WrapperSha; $TestRepository=$PythonWrapperRepository
    }
    $result=[pscustomobject]@{root=[IO.Path]::GetFullPath($TestRoot);sha=$TestSha;repository=$TestRepository;selection_id=$TestSelectionId;contract_sha256='';contract=$product}
    Assert-PythonTestSource $result
    if ($explicit) {
        $path=Join-Path $result.root 'conformance/test-contract.json'
        $result.contract=Read-PythonTestContract $path
        $result.contract_sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
    }
    $result
}
function Assert-PythonTestEvidencePair($Single,$Multi) {
    $fields=@('test_root','test_sha','test_repository','test_selection_id','test_contract_sha256')
    # Legacy evidence remains readable. Any new source field requires the complete binding.
    $hasAny=@($fields | Where-Object { $Single.PSObject.Properties[$_] -or $Multi.PSObject.Properties[$_] }).Count
    if (!$hasAny) { return }
    foreach ($field in $fields) {
        if (!$Single.PSObject.Properties[$field] -or !$Multi.PSObject.Properties[$field] -or $Single.$field -cne $Multi.$field) { throw "Multi-stage test source differs or is missing: $field" }
    }
    Assert-PythonSha $Single.test_sha
    if (!$Single.test_root -or $Single.test_repository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid test source evidence.' }
    if ($Single.test_selection_id) {
        if ($Single.test_selection_id -cnotmatch '^[0-9a-f]{64}$' -or $Single.test_contract_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Incomplete selected test evidence.' }
    } elseif ($Single.test_contract_sha256 -or $Single.test_sha -cne $Single.wrapper_sha -or $Single.test_repository -cne $PythonWrapperRepository) {
        throw 'Nondefault test source requires a selection binding.'
    }
}
