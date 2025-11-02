#region const
enum ItemType {
    dn;
    s;
    i;
    p;
}

enum DnItemInfo {
    it;
    k;
    p;
    v;
    vt;
}

enum DnPath {
    PathType;
    SectionPart;
    ItemPart;
    PropertyPart;
    ParentPath;
}

enum FileFormatEnum {
    psd1;
    json;
    xml;
    csv;
}

enum ValueType {
    Hashtable;
    String;
    Int32;
    Double;
    Boolean;
}

Set-Variable -Name 'PathDelimiter' -Value '/' -Option ReadOnly

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

function Get-DnPath {
    param (
        [Parameter(Mandatory = $true)] [string] $Path
    )
    Begin {
        $parts = $Path -split [regex]::Escape($PathDelimiter);
        $count = ($parts).Count;
        if ($count -gt 3) { throw "Incorrect path '$path'." }
        $parts | ForEach-Object { if ([string]::Empty -eq $_) {throw "Incorrect path '$path'."}}
    }

    End {
        return [PSCustomObject] @{ 
            [DnPath]::PathType = ($count -eq 1) ? [ItemType]::s : (($count -eq 2) ? [ItemType]::i : [ItemType]::p); 
            [DnPath]::SectionPart = $parts[0]; 
            [DnPath]::ItemPart = $count -gt 1 ? $parts[1] : $null ; 
            [DnPath]::PropertyPart = $count -gt 2 ? $parts[2] : $null ;
            [DnPath]::ParentPath = ($count -eq 1) ? $null : (($count -eq 2) ? $parts[0] : $parts[0] + $PathDelimiter + $parts[1]); 
            }        
    }
}

function New-DnItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)] [string] 
        [Alias("it")]
        [ValidateScript({ 
            ($_ -eq [ItemType]::dn) -or 
            ($_ -eq [ItemType]::s) -or 
            ($_ -eq [ItemType]::i) -or 
            ($_ -eq [ItemType]::p)
        })] $ItemType = [ItemType]::p,

        [Parameter(Mandatory = $true)] [Alias("k")] [string] $Key = $null,

        [Parameter(Mandatory = $false)] [Alias("p")] [string] $Path,

        [Parameter(Mandatory = $true)] 
        [Alias("v")]
        [ValidateScript({ 
            ($_ -is [hashtable]) -or 
            ($_ -is [string]) -or 
            ($_ -is [int]) -or 
            ($_ -is [double]) -or
            ($_ -is [bool])
        })] $Value

    )

    Begin {
        if ($ItemType -eq [ItemType]::p) {
            if ($Value -is [hashtable]) { throw "Incorrect Value type." }
        }
        elseif (($ItemType -eq [ItemType]::i) -or ($ItemType -eq [ItemType]::s) -or ($ItemType -eq [ItemType]::dn)) {
            if (-not ($Value -is [hashtable])) { throw "Incorrect Value type." }
        }      
        else { throw "Unhandled ItemType." }
    }

    Process {
    }

    End {
        Write-Output [PSCustomObject] @{ 
            [DnItemInfo]::it = $ItemType; 
            [DnItemInfo]::k = $Key;
            [DnItemInfo]::p = $Path; 
            [DnItemInfo]::v = $Value;
            [DnItemInfo]::vt = ($val.GetType().ToString() -split "\.") | Select-Object -Last 1
        }
    }
}

Set-Alias -Name ndni -Value New-DnItem

#endregion

#region l-1
function Import-Dn {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.IO.FileInfo] $FileInfo
    )
    Begin {
    }

    Process {
        try {
            $ext = $FileInfo.Extension;
            switch ($ext) {
                { $_ -eq ("." + [FileFormatEnum]::psd1) } { 
                    $dn = Import-PowerShellDataFile -Path $FileInfo.FullName ;
                    break; 
                }
                default { throw "File format '$ext' not supported." }
            }
            ndni -it [ItemType]::dn -k $null -p $FileInfo.FullName -v $dn;
        }
        catch {
            Write-Error $_
        }
    }

    End {
    }
}

Set-Alias -Name ipdn -Value Import-Dn

function Get-DnItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [PSCustomObject] $Dn,
        [Parameter(Mandatory = $true)] [string] $Path
    )

    Begin {
        $dnPath = Get-DnPath -Path $Path;
    }

    Process {
        [hashtable] $Root = $dn.v;
        $MatchingSectionKeys = $Root.Keys | Where-Object { $_ -like $dnPath.SectionPart }

        foreach ($SectionKey in $MatchingSectionKeys) {
            $Section = $Root[$SectionKey];
            if ($dnPath.PathType -eq [ItemType]::s) {
                ndni -it ([ItemType]::s) -k $SectionKey -p $SectionKey -v $Section                    
            }
            else {
                $MatchingItemKeys = $Section.Keys | Where-Object { $_ -like $dnPath.ItemPart }
                foreach ($ItemKey in $MatchingItemKeys) {
                    $Item = $Section[$ItemKey];              
                    if ($dnPath.PathType -eq [ItemType]::i) {
                        $FullPath = "${SectionKey}${PathDelimiter}${ItemKey}";
                        ndni -it ([ItemType]::i) -k $ItemKey -p $FullPath -v $Item                            
                    }
                    else {
                        $MatchingPropertyKeys = $Item.Keys | Where-Object { $_ -like $dnPath.PropertyPart }
                        foreach ($PropertyKey in $MatchingPropertyKeys) {
                            $Property = $Item[$PropertyKey];
                            $FullPath = "${SectionKey}${PathDelimiter}${ItemKey}${PathDelimiter}${PropertyKey}";
                            ndni -it ([ItemType]::p) -k $PropertyKey -p $FullPath -v $Property
                        }
                    }
                }
            }
        }
    }

    End {
    }
}

Set-Alias -Name gdni -Value Get-DnItem

function Join-DnItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [Alias("child")] [PSCustomObject] $ChildItem,
        [Parameter(Mandatory = $true)] [Alias("parent")] [PSCustomObject] $ParentItem,
        [Parameter(Mandatory = $false)] [Alias("no")] [switch] $NotOverride,
        [Parameter(Mandatory = $false)] [Alias("nocopy")] [switch] $NoCopyHashtable
    )

    Begin {
    }

    Process {
        # validation of PSCustomObject not possible in param script
        if ( -not @([ItemType]::s, [ItemType]::i, [ItemType]::p).Contains($ChildItem.it))  { throw "Invalid Item Type." }
        $validBind = (
            ($ParentItem.it -eq [ItemType]::dn -and $ChildItem.it -eq [ItemType]::s) -or
            ($ParentItem.it -eq [ItemType]::s -and $ChildItem.it -eq [ItemType]::i) -or
            ($ParentItem.it -eq [ItemType]::i -and $ChildItem.it -eq [ItemType]::p)
        )
        if (-not $validBind)  { throw "Invalid operation." }

        if ($NotOverride -and $ParentItem.v.ContainsKey($ChildItem.k)) { throw "Overriding prohibited." }
        else {
            $ParentItem[$ChildItem.k] = ($NoCopyHashtable) ? $ChildItem.v : (Copy-HashtableDeep -InputObject $ChildItem.v );
        }        
    }

    End {
        Write-Output $ParentItem;
    }
}

Set-Alias -Name jdni -Value Set-DnItem

function Remove-DnItem {
    [CmdletBinding()]
        param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [PSCustomObject] $Dn,
        [Parameter(Mandatory = $true)] [string] $Path
    )

    Begin {
        $dnPath = Get-DnPath -Path $Path;
    }

    Process {
        [hashtable] $Root = $dn.v;
        $MatchingSectionKeys = $Root.Keys | Where-Object { $_ -like $dnPath.SectionPart }

        foreach ($SectionKey in $MatchingSectionKeys) {
            if ($dnPath.PathType -eq [ItemType]::s) {
                $Root.Remove($SectionKey);                   
            }
            else {
                $Section = $Root[$SectionKey];                
                $MatchingItemKeys = $Section.Keys | Where-Object { $_ -like $dnPath.ItemPart }
                foreach ($ItemKey in $MatchingItemKeys) {
                    if ($dnPath.PathType -eq [ItemType]::i) {
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
        Write-Output $Dn;
    }
}

Set-Alias -Name rdni -Value Remove-DnItem

#endregion

#region l-2

#endregion

Export-ModuleMember -Function *
Export-ModuleMember -Alias *

Write-Host "DataNode imported"