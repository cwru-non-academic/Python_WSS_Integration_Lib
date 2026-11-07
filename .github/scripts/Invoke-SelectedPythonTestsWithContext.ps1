[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CoreRoot,
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$RootsPath,
    [Parameter(Mandatory)][string]$WorkRoot,
    [ValidateSet('committed','candidate')][string]$Mode='committed',
    [string]$ArtifactRoot='',[string]$CandidatePath='',[string]$PythonExe='python'
)
. "$PSScriptRoot/PythonSelectedContext.ps1"
Invoke-PythonSelectedWithContext @PSBoundParameters
