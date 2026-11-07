. "$PSScriptRoot/SelectedTestContext.ps1"

function Invoke-SelectedPythonRunner([hashtable]$Options) {
    # Authentication credentials belong to trusted Core calls, never selected code.
    # Use a child process so PowerShell's dynamic scope cannot expose saved values.
    $names=@('GH_TOKEN','GITHUB_TOKEN','WSS_TEST_VARIABLE_READ_TOKEN')
    $saved=@{}
    try {
        foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name);[Environment]::SetEnvironmentVariable($name,$null)}
        $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'Invoke-DotNetConformance.ps1'))
        foreach($key in $Options.Keys){$arguments+="-$key";$arguments+=[string]$Options[$key]}
        & (Join-Path $PSHOME 'pwsh.exe') @arguments
        if($LASTEXITCODE -ne 0){throw 'Mandatory or selected Python conformance failed; no selection evidence emitted.'}
    } finally {
        foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$saved[$name])}
    }
}

function Invoke-PythonSelectedWithContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CoreRoot,
        [Parameter(Mandatory)][string]$ContextPath,
        [Parameter(Mandatory)][string]$RootsPath,
        [Parameter(Mandatory)][string]$WorkRoot,
        [ValidateSet('committed','candidate')][string]$Mode='committed',
        [string]$ArtifactRoot='',[string]$CandidatePath='',
        [string]$PythonExe='python'
    )
    $ErrorActionPreference='Stop'
    $binding=Invoke-ReviewedSelectionCore $CoreRoot inspect 'python-wrapper' $ContextPath $RootsPath
    $roots=Get-Content -LiteralPath $RootsPath -Raw | ConvertFrom-Json
    $wrapper=Get-SelectedProduct $roots 'cwru-non-academic/Python_WSS_Integration_Lib'
    $fixture=Get-SelectedProduct $roots 'cwru-non-academic/CSharp_WSS_Integration_Lib'
    if(Test-Path -LiteralPath $WorkRoot){throw 'Selected validation work directory must be new.'}
    $work=[IO.Path]::GetFullPath($WorkRoot)
    foreach($source in @($roots.test_root)+@($roots.products.path)+@($CoreRoot)){
        $path=[IO.Path]::GetFullPath($source)
        if($work -eq $path -or $work.StartsWith($path+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
            throw 'Validation output must stay outside every immutable source checkout.'
        }
    }
    $options=@{WrapperRoot=$wrapper.path;WrapperSha=$wrapper.commit;FixtureRoot=$fixture.path;ConfigPath=(Join-Path $wrapper.path '.github/python-ci.json');OutputRoot=(Join-Path $work 'baseline');Mode=$Mode;PythonExe=$PythonExe;Role='wrapper';Stage='all'}
    if($Mode -ceq 'candidate'){
        if(!$ArtifactRoot -or !$CandidatePath){throw 'Candidate tests require the existing authenticated resolver output.'}
        $cli=Get-SelectedProduct $roots 'cwru-non-academic/CLI_Python_WSS_Application'
        $options.CliRoot=$cli.path;$options.CliSha=$cli.commit
        $options.ArtifactRoot=$ArtifactRoot;$options.CandidatePath=$CandidatePath
    } elseif($ArtifactRoot -or $CandidatePath){throw 'Committed tests cannot accept candidate payload overrides.'}
    # Baseline is unchanged and mandatory. Selection adds a second suite; never replaces it.
    Invoke-SelectedPythonRunner $options
    $options.OutputRoot=Join-Path $work 'selected'
    $options.TestRoot=$roots.test_root;$options.TestSha=$binding.test_commit
    $options.TestRepository=$binding.test_repository;$options.TestSelectionId=$binding.selection_id
    Invoke-SelectedPythonRunner $options
    # Core authenticates context again and revalidates exact products/tests after execution.
    Invoke-ReviewedSelectionCore $CoreRoot evidence 'python-wrapper' $ContextPath $RootsPath (Join-Path $work 'selection/evidence.json')
}
