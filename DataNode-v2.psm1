#region const
enum ChildType { Section; Item; Property; EndOfSection; EndOfItem; }
enum FileFormatEnum {psd1; json; xml; csv; }
enum ValueType { Hashtable; String; Int32; Double; Boolean; }

Set-Variable -Name 'PathDelimiter' -Value ':' -Option ReadOnly
#endregion

#region l-0
function Copy-HashtableDeep {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$InputObject
    )

    $serialized = [System.Management.Automation.PSSerializer]::Serialize($InputObject)
    $deepCopy = [System.Management.Automation.PSSerializer]::Deserialize($serialized)
    return $deepCopy
}

function ConvertTo-DNPath {
    param (
        [Parameter(Mandatory = $true)] [Alias("P")]
        [ValidateScript({  -not [string]::IsNullOrEmpty($_) })]
        [string] $Path
    )

    $parts = $Path -split [regex]::Escape($PathDelimiter);
    $count = ($parts).Count;
    if ($count -gt 3) { throw "Incorrect path '$path'." }
    $parts | ForEach-Object { if ([string]::Empty -eq $_) { throw "Incorrect path '$path'." } }

    return [PSCustomObject] @{ 
        PathType = ($count -eq 1) ? [ChildType]::Section : (($count -eq 2) ? [ChildType]::Item : [ChildType]::Property); 
        SectionPart = $parts[0]; 
        ItemPart = $count -gt 1 ? $parts[1] : $null ;
        PropertyPart = $count -gt 2 ? $parts[2] : $null ;
        ParentPath = ($count -eq 1) ? $null : (($count -eq 2) ? $parts[0] : $parts[0] + $PathDelimiter + $parts[1]); 
        Key = $parts | Select-Object -Last 1;
        FullPath = $Path;
    }        
}

function New-DN {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [Alias("FP")] [string] $FilePath,

        [Parameter(Mandatory = $false)] 
        [Alias("V")] 
        [hashtable] $Value
    )

    if ($Value -is [array]) {
        throw "Value must not be an array."
    }

    if ($null -eq $Value) { $Value = @{}; }

    return [PSCustomObject] @{ 
        ChildType = "DN"; 
        Path = $FilePath;
        Value = $Value;
        ValueType = ($Value.GetType().ToString() -split "\.") | Select-Object -Last 1
    }
}

Set-Alias -Name:ndn -Value:New-DN

#endregion

#region l-1
function New-DNChild {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [Alias("P")] [string] $Path,

        [Parameter(Mandatory = $false)] 
        [Alias("V")] 
        [ValidateScript({ ($_ -is [hashtable]) -or ($_ -is [string]) -or ($_ -is [int]) -or ($_ -is [double]) -or ($_ -is [bool]) })]
        [Object] $Value
    )

    $dnPath = ConvertTo-DNPath -Path:$Path;

    
    if ($Value -is [array]) {
        throw "Value must not be an array."
    }

    if ($null -eq $Value) {
        if ($dnPath.PathType -eq [ChildType]::Property) { $Value = [string]::Empty; } 
        else { $Value = @{}; }
    }

    if ($dnPath.PathType -eq [ChildType]::Property) {
        if ($Value -is [hashtable]) { throw "Incorrect Value Type." }
    }
    elseif (-not ($Value -is [hashtable])) { throw "Incorrect Value type." }  

    return [PSCustomObject] @{ 
        ChildType = $dnPath.PathType; 
        Path = $dnPath;
        Value = $Value;
        ValueType = ($Value.GetType().ToString() -split "\.") | Select-Object -Last 1
    }
}

Set-Alias -Name:ndnc -Value:New-DNChild

function Import-DN {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.IO.FileInfo] $FileInfo
    )

    Process {
        try {
            $ext = $FileInfo.Extension;
            switch ($ext) {
                { $_ -eq ("." + [FileFormatEnum]::psd1) } { 
                    $root = Import-PowerShellDataFile -Path:($FileInfo.FullName) -SkipLimitCheck ;
                    break; 
                }
                default { throw "File format '$ext' not supported." }
            }
            ndn -FP:$FileInfo.FullName -V:$root | Write-Output;
        }
        catch {
            Write-Error $_
        }
    }
}

Set-Alias -Name:impdn -Value:Import-DN

function Get-DNChildItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
        [ValidateScript({ "DN" -eq $_.ChildType })]
        [PSCustomObject] $DN,

        [Parameter(Mandatory = $true)] [Alias("P")] [string] $Path,

        [Parameter(Mandatory = $false)] [switch] $AddParents
    )

    $dnPath = ConvertTo-DNPath -Path:$Path;
    $output = @();

        [hashtable] $Root = $DN.V;
        $MatchingSectionKeys = $Root.Keys | Where-Object { $_ -like $dnPath.SectionPart }

        foreach ($SectionKey in $MatchingSectionKeys) {
            $Section = $Root[$SectionKey];
            if ([ChildType]::($dnPath.PathType) -eq [ChildType]::S) {
                $output += (ndni -IT:([ChildType]::S) -K:$SectionKey -P:$SectionKey -V:$Section)               
            }
            else {
                if ($AddParents) { $output += (ndni -IT:([ChildType]::S) -K:$SectionKey -P:$SectionKey -V:$Section) ; }
                $MatchingItemKeys = $Section.Keys | Where-Object { $_ -like $dnPath.ItemPart }
                foreach ($ItemKey in $MatchingItemKeys) {
                    $ItemPath = "${SectionKey}${PathDelimiter}${ItemKey}";                    
                    $Item = $Section[$ItemKey];              
                    if ([ChildType]::($dnPath.PathType) -eq [ChildType]::I) {
                        $output += (ndni -IT:([ChildType]::I) -K:$ItemKey -P:$ItemPath -V:$Item )                      
                    }
                    else {
                        if ($AddParents) { $output += (ndni -IT ([ChildType]::I) -K:$ItemKey -P:$ItemPath -V:$Item)  }
                        $MatchingPropertyKeys = $Item.Keys | Where-Object { $_ -like $dnPath.PropertyPart }
                        foreach ($PropertyKey in $MatchingPropertyKeys) {
                            $PropertyPath = "${SectionKey}${PathDelimiter}${ItemKey}${PathDelimiter}${PropertyKey}";                            
                            $Property = $Item[$PropertyKey];
                            $output += (ndni -IT:([ChildType]::P) -K:$PropertyKey -P:$PropertyPath -V:$Property)
                        }
                    }
                    if ($AddParents) { $output += (ndni -IT ([ChildType]::EoI) -K $ItemKey -P $ItemPath -V $Item)  }
                }
            }
            if ($AddParents) { $output += (ndni -IT:([ChildType]::EoS) -K:$SectionKey -P:$SectionKey -V:$Section)  }
        }
        return $output;
}

Set-Alias -Name:gdnci -Value:Get-DNChildItem

function Join-DNItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [Alias("Child")] [PSCustomObject] $ChildItem,
        [Parameter(Mandatory = $true)] [Alias("Parent")] [PSCustomObject] $ParentItem,
        [Parameter(Mandatory = $false)] [Alias("NOvr")] [switch] $NotOverride,
        [Parameter(Mandatory = $false)] [Alias("NoCopy")] [switch] $NoCopyHashtable
    )

    Process {
        # validation of PSCustomObject not possible in param script
        if ( -not @([ChildType]::S, [ChildType]::I, [ChildType]::P).Contains([ChildType]::($ChildItem.IT)))  { throw "Invalid Item Type." }
        $validBind = (
            ([ChildType]::($ParentItem.IT) -eq [ChildType]::DN -and [ChildType]::($ChildItem.IT) -eq [ChildType]::S) -or
            ([ChildType]::($ParentItem.IT) -eq [ChildType]::S -and [ChildType]::($ChildItem.IT) -eq [ChildType]::I) -or
            ([ChildType]::($ParentItem.IT) -eq [ChildType]::I -and [ChildType]::($ChildItem.IT) -eq [ChildType]::P)
        )
        if (-not $validBind)  { throw "Invalid operation." }

        if ($NotOverride -and $ParentItem.V.ContainsKey($ChildItem.K)) { throw "Overriding prohibited." }
        else {
            if ([ChildType]::($ChildItem.IT) -eq [ChildType]::P) { $ParentItem.V[$ChildItem.K] = $ChildItem.V }
            else { $ParentItem.V[$ChildItem.k] = (($NoCopyHashtable) ? $ChildItem.V : (Copy-HashtableDeep -InputObject:$ChildItem.V )); }
        }        
    }

    End {
        Write-Output $ParentItem;
    }
}

Set-Alias -Name:jdni -Value:Join-DnItem

function Remove-DNChildItem {
    [CmdletBinding()]
        param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
        [ValidateScript({ [ChildType]::($_.IT) -eq [ChildType]::DN })]
        [PSCustomObject] $DN,
        [Parameter(Mandatory = $true)] [Alias("P")] [string] $Path
    )

    Begin {
        $dnPath = Get-DNPath -Path:$Path;
    }

    Process {
        [hashtable] $Root = $DN.V;
        $MatchingSectionKeys = $Root.Keys | Where-Object { $_ -like $dnPath.SectionPart }

        foreach ($SectionKey in $MatchingSectionKeys) {
            if ([ChildType]::($dnPath.PathType) -eq [ChildType]::S) {
                $Root.Remove($SectionKey);                   
            }
            else {
                $Section = $Root[$SectionKey];                
                $MatchingItemKeys = $Section.Keys | Where-Object { $_ -like $dnPath.ItemPart }
                foreach ($ItemKey in $MatchingItemKeys) {
                    if ([ChildType]::($dnPath.PathType) -eq [ChildType]::I) {
                        $Section.Remove($ItemKey);                            
                    }
                    else {
                        $Item = $Section[$ItemKey];                         
                        $MatchingPropertyKeys = $Item.Keys | Where-Object { $_ -like $dnPath.PropertyPart }
                        foreach ($PropertyKey in $MatchingPropertyKeys) {
                            $Item.Remove($PropertyKey);
                        }
                        # if after romoving property, item remains empty, remove it
                        if ($Item.Keys.Count -eq 0) { $Section.Remove($ItemKey); }
                    }
                }
                # if after romoving item, section remains empty, remove it
                if ($Section.Keys.Count -eq 0) { $Value.Remove($SectionKey); }
            }
        }
    }

    End {
        Write-Output $DN;
    }
}

Set-Alias -Name:rmdnci -Value:Remove-DNChildItem

#endregion

#region l-2
function Get-DNSection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
        [ValidateScript({ "DN" -eq $_.ChildType })]
        [PSCustomObject] $DN,

        [Parameter(Mandatory = $true)] [Alias("P")] [PSCustomObject] $DNPath,

        [Parameter(Mandatory = $false)] [Alias("OC")] [System.Collections.Generic.List[PSCustomObject]] $OutputCollector ,

        [Parameter(Mandatory = $false)] [switch] $AddParents
    )

    Begin {
        $output = New-Object 'System.Collections.Generic.List[PSCustomObject]';
        if ($null -eq $OutputCollector) { $OutputCollector = New-Object 'System.Collections.Generic.List[PSCustomObject]'; }
    }

    Process {
        $value = $DN.Value;        
        $matchingSectionKeys = $value.Keys | Where-Object { $_ -like $DNPath.SectionPart }
        foreach ($sectionKey in $matchingSectionKeys) {
            $section = $value[$sectionKey];
            $output.Add((ndnc -P:$sectionKey -V:$section));    
        }
    }
    End {
        if ([ChildType]::($DNPath.PathType) -eq [ChildType]::Section) { 
            $OutputCollector.AddRange($output);
        }
        $output | Write-Output;
    }
}

Set-Alias -Name:gdns -Value:Get-DNSection

function Export-DN {
    [CmdletBinding()]
    param (
        [ValidateScript({ [ChildType]::($_.IT) -eq [ChildType]::DN })]
        [Parameter(Mandatory = $true)] [PSCustomObject] $DN,
        [Parameter(Mandatory = $false)] [Alias("FP")] [string] $FilePath
    )

    try {
        $FilePath = $FilePath ?? $DN.P
        $ext = [System.IO.Path]::GetExtension($FilePath);
        switch ($ext) {
            { $_ -eq ("." + [FileFormatEnum]::psd1) } { 
                $output = "@{`n";
                gdnci -DN:$DN -P:"*${PathDelimiter}*${PathDelimiter}*" -AddParents |
                ForEach-Object {
                    $dni = $_;
                    switch ($dni.it) {
                        { $_ -eq [ChildType]::S } { $output += "`t$($dni.K) = @{`n"; }
                        { $_ -eq [ChildType]::I } { $output += "`t`t$($dni.K) = @{`n"; }
                        { $_ -eq [ChildType]::P } { 
                            $textDelimiter = $dni.VT -eq [ValueType]::String ? "'" : ""
                            $output += "`t`t`t$($dni.K) = ${textDelimiter}$($dni.V)${textDelimiter};`n"; 
                        }
                        { $_ -eq [ChildType]::EoI } { $output += "`t`t};`n"; }                        
                        { $_ -eq [ChildType]::EoS } { $output += "`t};`n"; }
                    }
                }
                $output += "}";
                break; 
            }
            default { throw "File format '$ext' not supported." }
        }
    }
    catch {
        Write-Error $_
    }        

    Set-Content -Path:$FilePath -Value:$output;
    Get-Item -Path:$FilePath;
}

Set-Alias -Name:expdn -Value:Export-DN

function Set-DNItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [Alias("I")] [PSCustomObject] $ChildItem,
        [Parameter(Mandatory = $true)] [PSCustomObject] $DN,
        [Parameter(Mandatory = $false)] [Alias("NOvr")] [switch] $NotOverride,
        [Parameter(Mandatory = $false)] [Alias("NoCopy")] [switch] $NoCopyHashtable
    )

    Process {
        $iPath = Get-DNPath -Path $ChildItem.P;
        [hashtable] $Root = $DN.V;

        if ([ChildType]::($dnPath.PathType) -eq [ChildType]::S) {
            jdni -Parent:$DN -Child:$ChildItem -NOvr:$NotOverride -NoCopy:$NoCopyHashtable;
            return;
        }
        else {
            if (-not $Root.ContainsKey($iPath.SectionPart)) { $Root[$iPath.SectionPart] = @{}; }            
            $Section = gdnci -DN:$DN -Path:($iPath.SectionPart) ;
            if ([ChildType]::($dnPath.PathType) -eq [ChildType]::I) {
                jdni -Parent:$Section -Child:$ChildItem -NOvr:$NotOverride -NoCopy:$NoCopyHashtable | out-null;
                return;
            }
            else {
                if (-not $Section.V.ContainsKey($iPath.ItemPart)) { $Section.V[$iPath.ItemPart] = @{}; }  
                $Item = gdnci -DN:$DN -Path:("$($iPath.SectionPart)${PathDelimiter}$($iPath.ItemPart)") ;
                jdni -Parent:$Item -Child:$ChildItem -NOvr:$NotOverride -NoCopy:$NoCopyHashtable | out-null;
                return;
            }
        }
    }

    End {
        Write-Output $DN;
    }
}

Set-Alias -Name:sdni -Value:Set-DnItem

#endregion

Export-ModuleMember -Function *
Export-ModuleMember -Alias *

Write-Host "DataNode imported"