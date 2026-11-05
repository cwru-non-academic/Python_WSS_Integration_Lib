. "$PSScriptRoot/wss-ci/Evidence.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-WssMacOSArchitectureProof([string]$Root,[ValidateSet('x64','arm64')][string]$Architecture,[string]$Repository,[string]$RunId,[string]$SourceSha) {
    $label=if($Architecture -ceq 'x64') {'Intel (x64)'} else {'Apple Silicon (arm64)'}
    try {
        foreach($name in @('outcome.json','platform.json','python-smoke.json','platform.trx')) {
            if(!(Test-Path -LiteralPath (Join-Path $Root $name) -PathType Leaf)) { throw "Missing $name" }
        }
        $outcome=Get-Content (Join-Path $Root 'outcome.json') -Raw | ConvertFrom-Json
        $proof=Get-Content (Join-Path $Root 'platform.json') -Raw | ConvertFrom-Json
        $smokePath=Join-Path $Root 'python-smoke.json'
        $smoke=Get-Content $smokePath -Raw | ConvertFrom-Json
        Assert-WssCiEvidenceFields $outcome @{schema='wss-macos-worker/v1';architecture=$Architecture;conclusion='success';repository=$Repository;run_id=$RunId;source_sha=$SourceSha}
        if($proof.schema -cne 'wss-python-platform/v2' -or $proof.run_repository -cne $Repository -or [string]$proof.run_id -cne $RunId -or $proof.run_sha -cne $SourceSha -or
            $proof.os -cnotlike 'macOS *' -or $proof.architecture -cne $Architecture -or $proof.execution -cne 'native' -or
            $smoke.schema -cne 'wss-python-smoke/v2' -or $smoke.os -cne 'darwin' -or $smoke.architecture -cne $Architecture -or
            $smoke.dotnet_process_architecture -cne $Architecture -or $smoke.os_architecture -cne $Architecture -or
            $smoke.runner_architecture -cne $Architecture -or $smoke.translated -cne $false -or $smoke.execution -cne 'native' -or $smoke.physical_io -cne $false) { throw 'Native Python/CLR/OS/runner architecture identity mismatch or emulated execution' }
        Assert-WssCiEvidenceFiles $Root @{'python-smoke.json'=$proof.python_smoke_sha256;'platform.trx'=$proof.platform_trx_sha256}
        if($proof.universal_contract -ceq 'macos-ble-v1') {
            if($smoke.macos_ble_declared -cne $true -or !$smoke.ble.StartsWith('passed:',[StringComparison]::Ordinal) -or !$proof.ble.StartsWith('passed:',[StringComparison]::Ordinal)) { throw 'Declared BLE native activation did not pass' }
            $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
            $reader=[Xml.XmlReader]::Create((Join-Path $Root 'platform.trx'),$settings)
            try {$trx=[Xml.XmlDocument]::new();$trx.XmlResolver=$null;$trx.Load($reader)} finally {$reader.Dispose()}
            $native=@($trx.SelectNodes("//*[local-name()='UnitTestResult' and @testName='FacadeLoadsCurrentPlatformBackendAndDependencies' and @outcome='Passed']"))
            if($native.Count -ne 1 -or @($trx.SelectNodes("//*[local-name()='UnitTestResult' and @outcome='Failed']")).Count) { throw 'Native backend fixture missing, skipped, failed or duplicated' }
            $coverage='packaged-native-ble-load'
        } elseif($proof.universal_contract -ceq 'legacy-v1') {
            if($smoke.macos_ble_declared -cne $false -or !$smoke.ble.StartsWith('unsupported:',[StringComparison]::Ordinal)) { throw 'Legacy payload must explicitly report BLE unsupported' }
            $coverage='legacy-no-macos-ble'
        } else { throw 'Unknown universal payload contract' }
        [pscustomobject]@{architecture=$Architecture;label=$label;execution='native';coverage=$coverage;proof=$proof;smoke=$smoke}
    } catch { throw "macOS $label`: $($_.Exception.Message)" }
}

function Get-WssMacOSPair([string]$Root,[string]$Repository,[string]$RunId,[string]$SourceSha) {
    $results=@();$errors=@()
    foreach($architecture in @('x64','arm64')) {
        try {$results+=Get-WssMacOSArchitectureProof (Join-Path $Root $architecture) $architecture $Repository $RunId $SourceSha}
        catch {$errors+=$_.Exception.Message}
    }
    if($errors.Count) { throw ($errors -join '; ') }
    $first=$results[0].proof;$second=$results[1].proof
    foreach($field in @('mode','wrapper_sha','cli_sha','fixture_sha','projection_sha256','universal_contract')) {
        if([string]$first.$field -cne [string]$second.$field) { throw "macOS Intel (x64) / Apple Silicon (arm64) proofs disagree: $field" }
    }
    $candidate=[ordered]@{}
    foreach($field in @('repository','commit','run_id','artifact_id','archive','sha256')) {
        if([string]$first.candidate.$field -cne [string]$second.candidate.$field) { throw "macOS Intel (x64) / Apple Silicon (arm64) candidate mismatch: $field" }
        $candidate[$field]=[string]$first.candidate.$field
    }
    $architectures=@()
    foreach($item in $results) {
        $files=@()
        foreach($name in @('outcome.json','platform.json','python-smoke.json','platform.trx')) {
            $relative="$($item.architecture)/$name"
            $files+=[ordered]@{path=$relative;sha256=(Get-FileHash (Join-Path $Root $relative)).Hash.ToLowerInvariant()}
        }
        $architectures+=[ordered]@{architecture=$item.architecture;execution=$item.execution;coverage=$item.coverage;files=$files}
    }
    [ordered]@{schema='wss-python-macos-pair/v1';repository=$Repository;run_id=$RunId;source_sha=$SourceSha;mode=$first.mode;wrapper_sha=$first.wrapper_sha;cli_sha=$first.cli_sha;fixture_sha=$first.fixture_sha;projection_sha256=$first.projection_sha256;universal_contract=$first.universal_contract;candidate=$candidate;architectures=$architectures}
}

function Assert-WssMacOSPair([string]$Root,[string]$Repository,[string]$RunId,[string]$SourceSha) {
    $expected=@('macos.json')+@('x64','arm64' | ForEach-Object {$arch=$_;@('outcome.json','platform.json','python-smoke.json','platform.trx') | ForEach-Object {"$arch/$_"}})
    $files=@(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')})
    if(@(Compare-Object $expected $files -CaseSensitive).Count) {throw 'Unexpected/incomplete macOS aggregate artifact inventory'}
    $manifest=Get-Content (Join-Path $Root 'macos.json') -Raw | ConvertFrom-Json
    $actual=Get-WssMacOSPair $Root $Repository $RunId $SourceSha
    if(($manifest | ConvertTo-Json -Depth 12 -Compress) -cne ($actual | ConvertTo-Json -Depth 12 -Compress)) { throw 'macOS aggregate manifest differs from exact architecture proofs/bytes' }
    $actual
}
