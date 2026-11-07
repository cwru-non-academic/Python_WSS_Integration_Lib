# Execute the actual Prepare/Publish bodies, replacing only their import with the
# already-loaded module so read-only transport/evidence test doubles remain active.
# These synthetic cases are contract regressions, never candidate acceptance proof.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. "$root/.github/scripts/PythonPromotion.ps1"
$modern=Get-Content "$root/.github/python-ci.json" -Raw
$temp=Join-Path ([IO.Path]::GetTempPath()) ('python-promotion-contract-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $temp
$keys=@('GITHUB_ACTIONS','GITHUB_REF','GITHUB_EVENT_NAME','GITHUB_REPOSITORY','GITHUB_SHA','GITHUB_WORKFLOW_SHA','GITHUB_WORKFLOW_REF','GITHUB_OUTPUT','PYTHON_PUSH_TOKEN','WSS_CI_CHANNEL')
$saved=@{}; foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key)}
function Invoke-PythonGh([string[]]$Arguments) {
    if ($Arguments.Count -ne 2 -or $Arguments[0] -cne 'api') { throw 'Unexpected network operation.' }
    $prefix="repos/cwru-non-academic/Python_WSS_Integration_Lib/contents/.github/python-ci.json?ref="
    if ($Arguments[1] -ceq ($prefix+('a'*40))) { $data=$script:approved }
    elseif ($Arguments[1] -ceq ($prefix+('b'*40))) { $data=$script:merged }
    else { throw 'Unapproved contract source/endpoint redirect.' }
    $bytes=[Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json -Depth 12))
    $prefixBytes=[Text.Encoding]::UTF8.GetBytes("blob $($bytes.Length)`0")
    $sha=[Convert]::ToHexString([Security.Cryptography.SHA1]::HashData([byte[]]($prefixBytes+$bytes))).ToLowerInvariant()
    if($script:case -ceq 'blob-mutation'){$sha='f'*40}
    $path=if($script:case -ceq 'path-redirect'){'other.json'}else{'.github/python-ci.json'}
    @{type='file';path=$path;sha=$sha;encoding='base64';content=[Convert]::ToBase64String($bytes)} | ConvertTo-Json
}
function Assert-PythonApproval($Approval,[string]$EvidenceRoot,$Config) {
    if($Config.dotnet_expected_cases.Count -ne 16 -or $Config.multidevice_expected_cases.Count -ne 6 -or
       $Config.fixture_commit -cne $Approval.fixture.commit -or $Config.fixture_sha256 -cne $Approval.fixture.sha256){throw 'Wrong evidence contract.'}
    $script:approvalChecked=$true
}
function Assert-PythonMergedWrapper([string]$Sha,[string]$PrNumber,$Approval) {
    if($Sha -cne ('b'*40) -or $PrNumber -cne '71'){throw 'Wrong merged wrapper binding.'}
    if($script:case -ceq 'unapproved-merge'){throw 'Synthetic merged wrapper authentication rejection.'}
    $script:mergeChecked=$true
}
function Get-PythonHead([string]$Repository){$env:GITHUB_SHA}
function Start-PythonPreflight { [pscustomobject]@{id='200'} }
function Assert-PythonMergedApplicationPreflight($Approval,$Role,$WrapperSha,$ApplicationSha,$RunId,$Root,$Config) {
    if(!$script:approvalChecked -or !$script:mergeChecked -or $Config.dotnet_expected_cases.Count -ne 16 -or
       $WrapperSha -cne ('b'*40) -or $ApplicationSha -cne $env:GITHUB_SHA -or $RunId -cne '200'){throw 'Required guard or candidate binding omitted.'}
    throw 'TEST_REACHED_GUARDED_PREFLIGHT'
}
$count=0
try {
    foreach($entrypoint in @('Prepare','Publish')) {
        $path=Join-Path $root ".github/scripts/$entrypoint-PythonPromotion.ps1"
        $text=[IO.File]::ReadAllText($path)
        $import='. "$PSScriptRoot/PythonPromotion.ps1"'
        if(! $text.Contains($import)){throw 'Entrypoint import changed; update regression harness.'}
        $entry=[scriptblock]::Create($text.Replace($import,''))
        foreach($role in @('cli','ros')) {
            foreach($script:case in @('valid-dev','valid-main','target-optout','wrapper-optout','target-sdk','target-python','target-channel','wrapper-channel','wrong-channel','fixture-mismatch','source-redirect','mutable-source','merge-redirect','contract-mutation','blob-mutation','path-redirect','missing-multi','duplicate-cases','target-mutation','unapproved-merge')) {
                $script:approvalChecked=$false; $script:mergeChecked=$false
                $script:approved=$modern|ConvertFrom-Json; $script:merged=$modern|ConvertFrom-Json
                $own=$modern|ConvertFrom-Json
                $own.dotnet_expected_cases=@($own.dotnet_expected_cases|Select-Object -First 10)
                $own.PSObject.Properties.Remove('multidevice_expected_cases')
                $own.fixture_commit='02172a64'+('0'*32); $own.fixture_sha256='1cdfb944'+('0'*56)
                $channel=if($case -in @('valid-main','target-channel','wrapper-channel')){'main'}else{'dev'}
                $mergeSha='b'*40
                $approval=[pscustomobject]@{schema='wss-python-promotion/v2';candidate=@{repository='cwru-non-academic/WSSCore';commit=('c'*40);run_id='123';artifact_id='456';archive='WSS-Universal-ci.zip';sha256=('d'*64)};wrapper=@{source_sha=('a'*40);preflight_run_id='100'};cli=@{source_sha=('e'*40);preflight_run_id='101'};ros=@{source_sha=('f'*40);preflight_run_id='102'};fixture=@{commit=$approved.fixture_commit;sha256=$approved.fixture_sha256};projection_sha256=('9'*64)}
                switch($case){
                    'target-optout' {$own.baseline_ready=$false}
                    'wrapper-optout' {$approved.baseline_ready=$false;$merged.baseline_ready=$false}
                    'target-sdk' {$own.dotnet_sdk='9.0.999'}
                    'target-python' {$own.python_version='3.11'}
                    'target-channel' {$own.channels=@('dev')}
                    'wrapper-channel' {$approved.channels=@('dev');$merged.channels=@('dev')}
                    'wrong-channel' {$channel='other'}
                    'fixture-mismatch' {$approval.fixture.sha256='0'*64}
                    'source-redirect' {$approval.wrapper.source_sha='0'*40}
                    'mutable-source' {$approval.wrapper.source_sha='dev'}
                    'merge-redirect' {$mergeSha='0'*40}
                    'contract-mutation' {$merged.dotnet_expected_cases[15]='changed'}
                    'missing-multi' {$approved.multidevice_expected_cases=@();$merged.multidevice_expected_cases=@()}
                    'duplicate-cases' {$approved.dotnet_expected_cases[15]=$approved.dotnet_expected_cases[0];$merged.dotnet_expected_cases[15]=$merged.dotnet_expected_cases[0]}
                }
                $target=Join-Path $temp "$entrypoint-$role-$case"
                $null=New-Item -ItemType Directory (Join-Path $target '.github') -Force
                $own|ConvertTo-Json -Depth 12|Set-Content (Join-Path $target '.github/python-ci.json')
                $null=& git -C $target init --quiet
                $null=& git -C $target add .
                $null=& git -C $target -c user.name=ContractTest -c user.email=contract@example.invalid commit --quiet -m fixture
                if($LASTEXITCODE -ne 0){throw 'Fixture creation failed.'}
                $env:GITHUB_SHA=(& git -C $target rev-parse HEAD).Trim()
                $env:GITHUB_ACTIONS='true';$env:GITHUB_REF="refs/heads/$channel";$env:WSS_CI_CHANNEL=$channel
                $env:GITHUB_EVENT_NAME='workflow_dispatch';$env:GITHUB_REPOSITORY=(Get-PythonApplication $role).repository
                $env:GITHUB_WORKFLOW_SHA=$env:GITHUB_SHA
                $env:GITHUB_WORKFLOW_REF="$env:GITHUB_REPOSITORY/.github/workflows/promote-integration.yml@refs/heads/main"
                $env:PYTHON_PUSH_TOKEN='unit-test-only';$env:GITHUB_OUTPUT=Join-Path $temp 'outputs'
                if($case -ceq 'target-mutation'){Add-Content (Join-Path $target '.github/python-ci.json') ' '}
                $work=Join-Path $temp ([guid]::NewGuid().ToString('N'))
                $json=$approval|ConvertTo-Json -Depth 12
                if($entrypoint -ceq 'Publish'){
                    $null=New-Item -ItemType Directory $work
                    $json|Set-Content (Join-Path $work 'approval.json')
                    @{no_op=$false;role=$role;source_sha=$env:GITHUB_SHA;wrapper_merge_sha=$mergeSha;wrapper_pr='71';application_preflight_run_id='200'}|ConvertTo-Json|Set-Content (Join-Path $work 'prepared.json')
                }
                $reason=''
                try {
                    if($entrypoint -ceq 'Prepare'){& $entry -Role $role -WorkRoot $work -RepositoryRoot $target -ApprovalJson $json -WrapperMergeSha $mergeSha -WrapperPr '71'}
                    else{& $entry -RepositoryRoot $target -WorkRoot $work}
                } catch {$reason=$_.Exception.Message}
                $valid=$case -in @('valid-dev','valid-main')
                if(!$reason -or (($reason -ceq 'TEST_REACHED_GUARDED_PREFLIGHT') -ne $valid)){throw "$entrypoint/$role/$case unexpected outcome: $reason"}
                $count++
            }
        }
    }
} finally {foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$saved[$key])}}
Write-Output "PASS: $count actual promotion entrypoint legacy-target/modern-candidate binding cases; no real dispatch/publication."