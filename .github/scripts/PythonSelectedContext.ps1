. "$PSScriptRoot/SelectedTestContext.ps1"

. "$PSScriptRoot/SelectedProcessIsolation.ps1"
function Invoke-SelectedPythonRunner([hashtable]$Options) {
    Invoke-CredentialFreeSelectedPowerShell (Join-Path $PSScriptRoot 'Invoke-ProfiledPythonConformance.ps1') $Options
}

function Get-PythonBaselineSnapshot([string]$Root) {
    if (!(Test-Path -LiteralPath $Root -PathType Container)) { throw 'Mandatory baseline output is missing.' }
    $evidence=Get-Content -LiteralPath (Join-Path $Root 'evidence.json') -Raw | ConvertFrom-Json
    $stages=if($evidence.profile -ceq 'layered-v1'){@('', 'multi')}elseif($evidence.profile -ceq 'legacy-v1'){@('')}else{throw 'Unknown baseline evidence profile.'}
    foreach($stage in $stages){foreach($name in @('evidence.json','results.xml','dotnet.log','projection.json')){
        if(!(Test-Path -LiteralPath (Join-Path (Join-Path $Root $stage) $name) -PathType Leaf)){throw 'Mandatory baseline evidence file is missing.'}
    }}
    $entries=@(Get-ChildItem -LiteralPath $Root -Recurse -Force)
    if((Get-Item -LiteralPath $Root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint -or @($entries | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Baseline output cannot contain redirected paths.'}
    @($entries | Where-Object {!$_.PSIsContainer} | ForEach-Object {
        [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')+'|'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    } | Sort-Object -CaseSensitive) -join "`n"
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
    $context=Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
    # Inspect authenticated this scope; a run-level selection never forces modern payload.
    $selectionCampaign=$context.scope -ceq 'campaign'
    if(Test-Path -LiteralPath $WorkRoot){throw 'Selected validation work directory must be new.'}
    $work=[IO.Path]::GetFullPath($WorkRoot)
    foreach($source in @($roots.test_root)+@($roots.products.path)+@($CoreRoot)){
        $path=[IO.Path]::GetFullPath($source)
        if($work -eq $path -or $work.StartsWith($path+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
            throw 'Validation output must stay outside every immutable source checkout.'
        }
    }
    $options=@{WrapperRoot=$wrapper.path;WrapperSha=$wrapper.commit;ConfigPath=(Join-Path $wrapper.path '.github/python-ci.json');OutputRoot=(Join-Path $work 'baseline');Mode=$Mode;PythonExe=$PythonExe;Role='wrapper';Stage='all';SelectionEnabledCampaign=$selectionCampaign}
    if($Mode -ceq 'candidate'){
        if(!$ArtifactRoot -or !$CandidatePath){throw 'Candidate tests require the existing authenticated resolver output.'}
        $cli=Get-SelectedProduct $roots 'cwru-non-academic/CLI_Python_WSS_Application'
        $options.CliRoot=$cli.path;$options.CliSha=$cli.commit
        $options.ArtifactRoot=$ArtifactRoot;$options.CandidatePath=$CandidatePath
    } elseif($ArtifactRoot -or $CandidatePath){throw 'Committed tests cannot accept candidate payload overrides.'}
    # Baseline is bootstrap-owned and mandatory. Selection adds a second suite; never replaces it.
    Invoke-SelectedPythonRunner $options
    $baselineRoot=$options.OutputRoot
    $baselineSnapshot=Get-PythonBaselineSnapshot $baselineRoot
    $options.OutputRoot=Join-Path $work 'selected'
    $options.TestRoot=$roots.test_root;$options.TestSha=$binding.test_commit
    $options.TestRepository=$binding.test_repository;$options.TestSelectionId=$binding.selection_id
    Invoke-SelectedPythonRunner $options
    if((Get-PythonBaselineSnapshot $baselineRoot) -cne $baselineSnapshot){throw 'Selected suite changed mandatory baseline output; no selection evidence emitted.'}
    # Core authenticates context again and revalidates exact products/tests after execution.
    Invoke-ReviewedSelectionCore $CoreRoot evidence 'python-wrapper' $ContextPath $RootsPath (Join-Path $work 'selection/evidence.json')
}
