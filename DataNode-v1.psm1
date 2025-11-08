#region const
enum ItemType { DN; S; I; P; EoS; EoI; }
enum ItemMember { IT; K; P; V; VT; }
enum DNPathMember { PathType; SectionPart; ItemPart; PropertyPart; ParentPath; }
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

function Get-DNPath {
    param (
        [Parameter(Mandatory = $true)] [Alias("P")] [string] $Path
    )

    $parts = $Path -split [regex]::Escape($PathDelimiter);
    $count = ($parts).Count;
    if ($count -gt 3) { throw "Incorrect path '$path'." }
    $parts | ForEach-Object { if ([string]::Empty -eq $_) { throw "Incorrect path '$path'." } }

    return [PSCustomObject] @{ 
        [DNPathMember]::PathType.ToString()     = ($count -eq 1) ? [ItemType]::S : (($count -eq 2) ? [ItemType]::I : [ItemType]::P); 
        [DNPathMember]::SectionPart.ToString()  = $parts[0]; 
        [DNPathMember]::ItemPart.ToString()     = $count -gt 1 ? $parts[1] : $null ; 
        [DNPathMember]::PropertyPart.ToString() = $count -gt 2 ? $parts[2] : $null ;
        [DNPathMember]::ParentPath.ToString()   = ($count -eq 1) ? $null : (($count -eq 2) ? $parts[0] : $parts[0] + $PathDelimiter + $parts[1]); 
    }        
}

function New-DNItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)] [string] 
        [Alias("IT")]
        [ValidateScript({ @([ItemType]::DN, [ItemType]::S, [ItemType]::I, [ItemType]::P, [ItemType]::EoS, [ItemType]::EoI).Contains([ItemType]::$_) })]
        $ItemType = [ItemType]::P,

        [Parameter(Mandatory = $false)] [Alias("K")] [string] $Key = $null,

        [Parameter(Mandatory = $false)] [Alias("P")] [string] $Path,

        [Parameter(Mandatory = $true)] 
        [Alias("V")] 
        [ValidateScript({ ($_ -is [hashtable]) -or ($_ -is [string]) -or ($_ -is [int]) -or ($_ -is [double]) -or ($_ -is [bool]) })]
        $Value
    )
    
    if ([ItemType]::$ItemType -eq [ItemType]::P) {
        if ($Value -is [hashtable]) { throw "Incorrect Value Type." }
    }
    elseif (-not ($Value -is [hashtable])) { throw "Incorrect Value type." }  

    return [PSCustomObject] @{ 
        [ItemMember]::IT.ToString() = $ItemType; 
        [ItemMember]::K.ToString() = $Key;
        [ItemMember]::P.ToString() = $Path; 
        [ItemMember]::V.ToString() = $Value;
        [ItemMember]::VT.ToString() = ($Value.GetType().ToString() -split "\.") | Select-Object -Last 1
    }
}

Set-Alias -Name:ndni -Value:New-DnItem

#endregion

#region l-1
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
                    $dn = Import-PowerShellDataFile -Path:($FileInfo.FullName) -SkipLimitCheck ;
                    break; 
                }
                default { throw "File format '$ext' not supported." }
            }
            ndni -IT:([ItemType]::DN) -K:$null -P:$FileInfo.FullName -V:$dn | Write-Output;
        }
        catch {
            Write-Error $_
        }
    }
}

Set-Alias -Name:impdn -Value:Import-Dn

function Get-DNChildItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] 
        [ValidateScript({ [ItemType]::($_.IT) -eq [ItemType]::DN })]
        [PSCustomObject] $DN,

        [Parameter(Mandatory = $true)] [Alias("P")] [string] $Path,

        [Parameter(Mandatory = $false)] [switch] $AddParents
    )

    $dnPath = Get-DNPath -Path:$Path;
    $output = @();

        [hashtable] $Root = $DN.V;
        $MatchingSectionKeys = $Root.Keys | Where-Object { $_ -like $dnPath.SectionPart }

        foreach ($SectionKey in $MatchingSectionKeys) {
            $Section = $Root[$SectionKey];
            if ([ItemType]::($dnPath.PathType) -eq [ItemType]::S) {
                $output += (ndni -IT:([ItemType]::S) -K:$SectionKey -P:$SectionKey -V:$Section)               
            }
            else {
                if ($AddParents) { $output += (ndni -IT:([ItemType]::S) -K:$SectionKey -P:$SectionKey -V:$Section) ; }
                $MatchingItemKeys = $Section.Keys | Where-Object { $_ -like $dnPath.ItemPart }
                foreach ($ItemKey in $MatchingItemKeys) {
                    $ItemPath = "${SectionKey}${PathDelimiter}${ItemKey}";                    
                    $Item = $Section[$ItemKey];              
                    if ([ItemType]::($dnPath.PathType) -eq [ItemType]::I) {
                        $output += (ndni -IT:([ItemType]::I) -K:$ItemKey -P:$ItemPath -V:$Item )                      
                    }
                    else {
                        if ($AddParents) { $output += (ndni -IT ([ItemType]::I) -K:$ItemKey -P:$ItemPath -V:$Item)  }
                        $MatchingPropertyKeys = $Item.Keys | Where-Object { $_ -like $dnPath.PropertyPart }
                        foreach ($PropertyKey in $MatchingPropertyKeys) {
                            $PropertyPath = "${SectionKey}${PathDelimiter}${ItemKey}${PathDelimiter}${PropertyKey}";                            
                            $Property = $Item[$PropertyKey];
                            $output += (ndni -IT:([ItemType]::P) -K:$PropertyKey -P:$PropertyPath -V:$Property)
                        }
                    }
                    if ($AddParents) { $output += (ndni -IT ([ItemType]::EoI) -K $ItemKey -P $ItemPath -V $Item)  }
                }
            }
            if ($AddParents) { $output += (ndni -IT:([ItemType]::EoS) -K:$SectionKey -P:$SectionKey -V:$Section)  }
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
        if ( -not @([ItemType]::S, [ItemType]::I, [ItemType]::P).Contains([ItemType]::($ChildItem.IT)))  { throw "Invalid Item Type." }
        $validBind = (
            ([ItemType]::($ParentItem.IT) -eq [ItemType]::DN -and [ItemType]::($ChildItem.IT) -eq [ItemType]::S) -or
            ([ItemType]::($ParentItem.IT) -eq [ItemType]::S -and [ItemType]::($ChildItem.IT) -eq [ItemType]::I) -or
            ([ItemType]::($ParentItem.IT) -eq [ItemType]::I -and [ItemType]::($ChildItem.IT) -eq [ItemType]::P)
        )
        if (-not $validBind)  { throw "Invalid operation." }

        if ($NotOverride -and $ParentItem.V.ContainsKey($ChildItem.K)) { throw "Overriding prohibited." }
        else {
            if ([ItemType]::($ChildItem.IT) -eq [ItemType]::P) { $ParentItem.V[$ChildItem.K] = $ChildItem.V }
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
        [ValidateScript({ [ItemType]::($_.IT) -eq [ItemType]::DN })]
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
            if ([ItemType]::($dnPath.PathType) -eq [ItemType]::S) {
                $Root.Remove($SectionKey);                   
            }
            else {
                $Section = $Root[$SectionKey];                
                $MatchingItemKeys = $Section.Keys | Where-Object { $_ -like $dnPath.ItemPart }
                foreach ($ItemKey in $MatchingItemKeys) {
                    if ([ItemType]::($dnPath.PathType) -eq [ItemType]::I) {
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
function Export-DN {
    [CmdletBinding()]
    param (
        [ValidateScript({ [ItemType]::($_.IT) -eq [ItemType]::DN })]
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
                        { $_ -eq [ItemType]::S } { $output += "`t$($dni.K) = @{`n"; }
                        { $_ -eq [ItemType]::I } { $output += "`t`t$($dni.K) = @{`n"; }
                        { $_ -eq [ItemType]::P } { 
                            $textDelimiter = $dni.VT -eq [ValueType]::String ? "'" : ""
                            $output += "`t`t`t$($dni.K) = ${textDelimiter}$($dni.V)${textDelimiter};`n"; 
                        }
                        { $_ -eq [ItemType]::EoI } { $output += "`t`t};`n"; }                        
                        { $_ -eq [ItemType]::EoS } { $output += "`t};`n"; }
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

        if ([ItemType]::($dnPath.PathType) -eq [ItemType]::S) {
            jdni -Parent:$DN -Child:$ChildItem -NOvr:$NotOverride -NoCopy:$NoCopyHashtable;
            return;
        }
        else {
            if (-not $Root.ContainsKey($iPath.SectionPart)) { $Root[$iPath.SectionPart] = @{}; }            
            $Section = gdnci -DN:$DN -Path:($iPath.SectionPart) ;
            if ([ItemType]::($dnPath.PathType) -eq [ItemType]::I) {
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