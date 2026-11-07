param([Parameter(Mandatory)][string]$MainRoot,[Parameter(Mandatory)][string]$DevRoot,[Parameter(Mandatory)][string]$MainResults,[Parameter(Mandatory)][string]$DevResults)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../PythonContract.ps1"
. "$PSScriptRoot/../PythonProfiles/Contract.ps1"
$temp=Join-Path ([IO.Path]::GetTempPath()) ('python-profile-proof-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$count=0
foreach($source in @(@($MainRoot,$MainResults),@($DevRoot,$DevResults))){
    $projection=Get-Content (Join-Path $source[0] '.github/python-candidate.json') -Raw | ConvertFrom-Json
    Assert-PythonProjection (Join-Path $source[0] 'Cs_Libraries') $projection
    $profile=Resolve-WssReviewedProfile (Join-Path $source[0] 'Cs_Libraries') $projection.candidate
    Assert-PythonProfileEvidence $source[1] $profile $projection;$count++
    $cases=@('profile','dll','producer','counts','fixture','inventory','selection','hash')
    if($profile.profile -ceq 'layered-v1'){$cases+=@('missing-multi','cross-stage-profile')}
    foreach($case in $cases){
        $copy=Join-Path $temp ($profile.profile+'-'+$case)
        $null=New-Item -ItemType Directory -Path $copy
        foreach($name in @('evidence.json','results.xml','dotnet.log','projection.json')){Copy-Item (Join-Path $source[1] $name) (Join-Path $copy $name)}
        if($profile.profile -ceq 'layered-v1'){
            $null=New-Item -ItemType Directory -Path (Join-Path $copy 'multi')
            foreach($name in @('evidence.json','results.xml','dotnet.log','projection.json')){Copy-Item (Join-Path $source[1] "multi/$name") (Join-Path $copy "multi/$name")}
        }
        $path=Join-Path $copy 'evidence.json';$proof=Get-Content $path -Raw | ConvertFrom-Json
        switch($case){
            'profile'{$proof.profile=if($profile.profile -ceq 'legacy-v1'){'layered-v1'}else{'legacy-v1'}}
            'dll'{$proof.core_dll_sha256='f'*64}
            'producer'{$proof.producer_commit='f'*40}
            'counts'{$proof.passed=1}
            'fixture'{$proof.fixture_sha256='f'*64}
            'selection'{$proof.PSObject.Properties.Remove('test_sha')}
            'hash'{$proof.log_sha256='f'*64}
            'missing-multi'{Remove-Item -LiteralPath (Join-Path $copy 'multi/evidence.json')}
            'cross-stage-profile'{$mp=Join-Path $copy 'multi/evidence.json';$m=Get-Content $mp -Raw | ConvertFrom-Json;$m.profile='legacy-v1';$m | ConvertTo-Json -Depth 10 | Set-Content $mp}
            'inventory'{
                $xmlPath=Join-Path $copy 'results.xml';[xml]$xml=Get-Content $xmlPath -Raw
                $nodes=@($xml.SelectNodes('//test-case'));$nodes[-1].SetAttribute('name',$nodes[0].GetAttribute('name'));$xml.Save($xmlPath)
                $proof.results_sha256=(Get-FileHash $xmlPath).Hash.ToLowerInvariant()
            }
        }
        $proof | ConvertTo-Json -Depth 10 | Set-Content $path
        $rejected=$false;try{Assert-PythonProfileEvidence $copy $profile $projection}catch{$rejected=$true}
        if(!$rejected){throw "Corrupt profile proof accepted: $($profile.profile)/$case"};$count++
    }
}
# Product inventory text cannot choose a profile; runtime remains independently fixed.
$c=Get-Content (Join-Path $MainRoot '.github/python-ci.json') -Raw | ConvertFrom-Json
$c.dotnet_expected_cases=@('untrusted-count-marker');$config=Join-Path $temp 'config.json';$c | ConvertTo-Json -Depth 8 | Set-Content $config
$null=Read-PythonProfileProductConfig $config
if((Get-PythonProfileContract 'legacy-v1').single_cases.Count -ne 10 -or (Get-PythonProfileContract 'layered-v1').multi_cases.Count -ne 16){throw 'Product count changed trusted inventory.'};$count++
$c.python_version='0.0';$c | ConvertTo-Json -Depth 8 | Set-Content $config
$rejected=$false;try{Read-PythonProfileProductConfig $config}catch{$rejected=$true};if(!$rejected){throw 'Invalid runtime accepted.'};$count++
Write-Output "PASS: $count real-profile evidence and product/config isolation checks; corrupt copies only."
