#region const
enum ItemType {
    dn;
    s;
    i;
    p;
}

enum dni {
    it;
    k;
    p;
    v;
    vt;
}

enum dnPath {
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
            [dnPath]::PathType = ($count -eq 1) ? [ItemType]::s : (($count -eq 2) ? [ItemType]::i : [ItemType]::p); 
            [dnPath]::SectionPart = $parts[0]; 
            [dnPath]::ItemPart = $count -gt 1 ? $parts[1] : $null ; 
            [dnPath]::PropertyPart = $count -gt 2 ? $parts[2] : $null ;
            [dnPath]::ParentPath = ($count -eq 1) ? $null : (($count -eq 2) ? $parts[0] : $parts[0] + $PathDelimiter + $parts[1]); 
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
        })] $Value,

        [Parameter(Mandatory = $false)] [Alias("nocopy")] [switch] $NoCopyHashtable
    )

    Begin {
        if ($ItemType -eq [ItemType]::p) {
            if ($Value -is [hashtable]) { throw "Incorrect Value type." }
            $val = $Value
        }
        elseif (($ItemType -eq [ItemType]::i) -or ($ItemType -eq [ItemType]::s) -or ($ItemType -eq [ItemType]::dn)) {
            if (-not ($Value -is [hashtable])) { throw "Incorrect Value type." }
            $val = ($NoCopyHashtable) ? $Value : (Copy-HashtableDeep -InputObject $Value )
        }      
        else { throw "Unhandled ItemType." }
    }

    Process {
    }

    End {
        Write-Output [PSCustomObject] @{ 
            [dni]::it = $ItemType; 
            [dni]::k = $Key;
            [dni]::p = $Path; 
            [dni]::v = $val;
            [dni]::vt = ($val.GetType().ToString() -split "\.") | Select-Object -Last 1
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
            ndni -it [ItemType]::dn -k $null -p $FileInfo.FullName -v $dn -nocopy;
        }
        catch {
            Write-Error $_
        }
    }

    End {
    }
}

Set-Alias -Name ipdn -Value Import-Dn

function Set-DnItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [Alias("i")] [PSCustomObject] $Item,
        [Parameter(Mandatory = $true)] [Alias("t")] [PSCustomObject] $TargetDn,
        [Parameter(Mandatory = $false)] [Alias("p")] [string] $TargetPath = $null,
        [Parameter(Mandatory = $false)] [Alias("no")] [switch] $NotOverride
    )

    Begin {
        # validation of PSCustomObject not possible in param script
        if ( -not @([ItemType]::s, [ItemType]::i, [ItemType]::p).Contains($Item.it))  { throw "Invalid Item Type." }
        if (-not ($TargetDn.it -eq [ItemType]::dn)) { throw "Invalid Target Type." }

        # for items returned from gdni, take parent path
        if ($null -eq $TargetPath) { $TargetPath = (Get-DnPath -Path $Item.p).ParentPath; }
        $dnPath = Get-DnPath -Path $TargetPath;
        $Root = $TargetDn.v;

        if ($null -eq $dnPath.ParentPath -and $Item.it -eq [ItemType]::s) {
            if ($NotOverride -and $Root.ContainsKey($Item.k)) { throw "Overriding prohibited." }
            else {
                $Root[$Item.k] = $Item.v;
            }
        }
        elseif ((-not ($null -eq $dnPath.ParentPath)) -and $dnPath.PathType -eq [ItemType]::s -and $Item.it -eq [ItemType]::i) {
            if (-not $Root.ContainsKey($dnPath.SectionPart)) { $Root[$dnPath.SectionPart] = @{} }
            $targetSection = $Root[$dnPath.SectionPart];
            if ($NotOverride -and $targetSection.ContainsKey($Item.k)) { throw "Overriding prohibited." }
            else {
                $targetSection[$Item.k] = $Item.v;
            }
        }
        elseif ((-not ($null -eq $dnPath.ParentPath)) -and $dnPath.PathType -eq [ItemType]::i -and $Item.it -eq [ItemType]::p) {
            if (-not $Root.ContainsKey($dnPath.SectionPart)) { $Root[$dnPath.SectionPart] = @{} }
            $targetSection = $Root[$dnPath.SectionPart];
            if (-not $targetSection.ContainsKey($dnPath.ItemPart)) { $targetSection[$dnPath.ItemPart] = @{} }
            $targetItem = $targetSection[$dnPath.ItemPart];
            if ($NotOverride -and $targetItem.ContainsKey($Item.k)) { throw "Overriding prohibited." }
            else {
                $targetItem[$Item.k] = $Item.v;
            }
        }
        else {
            throw "Invalid operation."
        }
    }

    Process {
    }

    End {
        Write-Output $TargetDn;
    }
}

Set-Alias -Name sdni -Value Set-DnItem

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
#endregion


Export-ModuleMember -Function *
Export-ModuleMember -Alias *

Write-Host "DataNode imported"