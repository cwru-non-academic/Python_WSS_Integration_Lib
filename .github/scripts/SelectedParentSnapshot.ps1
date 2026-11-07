# Parent-owned content snapshots. These protect authenticated inputs; they grant no authority.
function Assert-SelectedRegularPath([string]$Path) {
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    while($null -ne $item){
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Selected authority/baseline path is redirected.'}
        $parent=[IO.Path]::GetDirectoryName($item.FullName)
        if(!$parent -or $parent -ceq $item.FullName){break}
        $item=Get-Item -LiteralPath $parent -Force -ErrorAction Stop
    }
}
function Get-SelectedParentInventory([string[]]$Roots,[string[]]$Files=@()) {
    $entries=[Collections.Generic.List[string]]::new()
    foreach($root in $Roots){
        $root=[IO.Path]::GetFullPath($root)
        Assert-SelectedRegularPath $root
        if(!(Get-Item -LiteralPath $root -Force).PSIsContainer){throw 'Snapshot source root must be a directory.'}
        $entries.Add("$root|ROOT")
        $queue=[Collections.Generic.Queue[string]]::new();$queue.Enqueue($root)
        while($queue.Count){
            $directory=$queue.Dequeue()
            foreach($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop){
                if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Selected authority/baseline tree contains redirected paths.'}
                $relative=[IO.Path]::GetRelativePath($root,$item.FullName).Replace('\','/')
                if($item.PSIsContainer){$entries.Add("$root|D|$relative");$queue.Enqueue($item.FullName)}
                else{$hash=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash;$entries.Add("$root|F|$relative|$hash")}
            }
        }
    }
    foreach($file in $Files){
        $file=[IO.Path]::GetFullPath($file);Assert-SelectedRegularPath $file
        if((Get-Item -LiteralPath $file -Force).PSIsContainer){throw 'Snapshot authority input must be a regular file.'}
        $entries.Add("$file|INPUT|$((Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash)")
    }
    @($entries | Sort-Object -CaseSensitive)
}
function New-SelectedParentSnapshot([string[]]$Roots,[string[]]$Files=@()) {
    @{roots=@($Roots);files=@($Files);inventory=@(Get-SelectedParentInventory $Roots $Files)}
}
function Assert-SelectedParentSnapshot($Snapshot) {
    $current=@(Get-SelectedParentInventory $Snapshot.roots $Snapshot.files)
    if($current.Count -ne $Snapshot.inventory.Count){throw 'Selected child changed trusted parent inventory/content.'}
    for($i=0;$i -lt $current.Count;$i++){if($current[$i] -cne $Snapshot.inventory[$i]){throw 'Selected child changed trusted parent inventory/content.'}}
}
