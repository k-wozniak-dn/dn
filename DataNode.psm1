enum FileFormatEnum {
    psd1;
    json;
    xml;
    csv;
}

enum ItemType {
    DataNode;
    Section;
    Item;
    Property;
}

enum ValueType {
    Hashtable;
    String;
    Int32;
    Double;
    Boolean;
}


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
        $parts = $Path -split '[\\/]+';
        $count = ($parts).Count;
        if ($count -gt 3) { throw "Incorrect path '$path'." }
        $parts | ForEach-Object { if ([string]::Empty -eq $_) {throw "Incorrect path '$path'."}}

        return [PSCustomObject] @{ 
            "PathType" = ($count -eq 1) ? [ItemType]::Section : (($count -eq 2) ? [ItemType]::Item : [ItemType]::Property); 
            "Section" = $parts[0]; 
            "Item" = $count -gt 1 ? $parts[1] : $null ; 
            "Property" = $count -gt 2 ? $parts[2] : $null ;
            "ParentPath" = ($count -eq 1) ? $null : (($count -eq 2) ? $parts[0] : $parts[0] + "/" + $parts[1]); 
            }
    }
}

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
            $dnWrapper = [PSCustomObject] @{ "ItemType" = [ItemType]::DataNode ; "Path" = $FileInfo.FullName; "Value" = $dn; }
            Write-Output $dnWrapper             
        }
        catch {
            Write-Error $_
        }
    }

    End {
    }
}

Set-Alias -Name ipdn -Value Import-Dn

function New-DnItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)] [string] 
        [Alias("it")]
        [ValidateScript({ 
            ($_ -eq [ItemType]::Section) -or 
            ($_ -eq [ItemType]::Item) -or 
            ($_ -eq [ItemType]::Property)
        })] $ItemType = [ItemType]::Property,

        [Parameter(Mandatory = $true)] [Alias("k")] [string] $Key,

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
        if ($ItemType -eq [ItemType]::Section) {
            if (-not ($Value -is [hashtable])) { throw "Incorrect Value type." }
            $val = ($NoCopyHashtable) ? $Value : (Copy-HashtableDeep -InputObject $Value )
        }
        elseif ($ItemType -eq [ItemType]::Item) {
            if (-not ($Value -is [hashtable])) { throw "Incorrect Value type." }
            $val = ($NoCopyHashtable) ? $Value : (Copy-HashtableDeep -InputObject $Value )
        }
        elseif ($ItemType -eq [ItemType]::Property) {
            if ($Value -is [hashtable]) { throw "Incorrect Value type." }
            $val = $Value
        }
        else { throw "Unhandled ItemType." }
    }

    Process {
    }

    End {
        Write-Output [PSCustomObject] @{ 
            "ItemType" = $ItemType; 
            "Key" = $Key;
            "Path" = $Path; 
            "Value" = $val;
            "ValueType" = ($val.GetType().ToString() -split "\.") | Select-Object -Last 1
        }
    }
}

Set-Alias -Name ndni -Value New-DnItem

function Set-DnItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [Alias("i")] [PSCustomObject] $Item,
        [Parameter(Mandatory = $true)] [Alias("t")] [PSCustomObject] $TargetDn,
        [Parameter(Mandatory = $false)] [Alias("p")] [string] $TargetPath = $null,
        [Parameter(Mandatory = $false)] [Alias("no")] [switch] $NotOverride
    )

    Begin {
        if (-not (($Item.ItemType -eq [ItemType]::Section) -or 
            ($Item.ItemType -eq [ItemType]::Item) -or 
            ($Item.ItemType -eq [ItemType]::Property))) { throw "Invalid Item Type." }

        if (-not ($TargetDn.ItemType -eq [ItemType]::DataNode)) { throw "Invalid Target Type." }

        $dnPath = $null -eq $TargetPath ? (Get-DnPath -Path $Item.Path).ParentPath : (Get-DnPath -Path $TargetPath);

        if ($null -eq $dnPath -and $Item.ItemType -eq [ItemType]::Section) {
            if ($NotOverride -and $TargetDn.Value.ContainsKey($Item.Key)) { throw "Overriding prohibited." }
            else {
                $TargetDn.Value[$Item.Key] = $Item.Value;
            }
        }
        elseif ((-not ($null -eq $dnPath)) -and $dnPath.PathType -eq [ItemType]::Section -and $Item.ItemType -eq [ItemType]::Item) {
            if (-not $TargetDn.Value.ContainsKey($dnPath.Section)) { $TargetDn.Value[$dnPath.Section] = @{} }
            $targetSection = $TargetDn.Value[$dnPath.Section];
            if ($NotOverride -and $targetSection.ContainsKey($Item.Key)) { throw "Overriding prohibited." }
            else {
                $targetSection[$Item.Key] = $Item.Value;
            }
        }
        elseif ((-not ($null -eq $dnPath)) -and $dnPath.PathType -eq [ItemType]::Item -and $Item.ItemType -eq [ItemType]::Property) {
            if (-not $TargetDn.Value.ContainsKey($dnPath.Section)) { $TargetDn.Value[$dnPath.Section] = @{} }
            $targetSection = $TargetDn.Value[$dnPath.Section];
            if (-not $targetSection.ContainsKey($dnPath.Item)) { $targetSection[$dnPath.Item] = @{} }
            $targetItem = $targetSection[$dnPath.Item];
            if ($NotOverride -and $targetItem.ContainsKey($Item.Key)) { throw "Overriding prohibited." }
            else {
                $targetItem[$Item.Key] = $Item.Value;
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
        [hashtable] $Value = $dn.Value;
        $MatchingSectionKeys = $Value.Keys | Where-Object { $_ -like $dnPath.Section }

        foreach ($SectionKey in $MatchingSectionKeys) {
            if ($dnPath.PathType -eq [ItemType]::Section) {
                $Value.Remove($SectionKey);                   
            }
            else {
                $Section = $Value[$SectionKey];                
                $MatchingItemKeys = $Section.Keys | Where-Object { $_ -like $dnPath.Item }
                foreach ($ItemKey in $MatchingItemKeys) {
                    if ($dnPath.PathType -eq [ItemType]::Item) {
                        $Section.Remove($ItemKey);                            
                    }
                    else {
                        $Item = $Section[$ItemKey];                         
                        $MatchingPropertyKeys = $Item.Keys | Where-Object { $_ -like $dnPath.Property }
                        foreach ($PropertyKey in $MatchingPropertyKeys) {
                            $Item.Remove($PropertyKey);
                        }
                    }
                }
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
        [hashtable] $Value = $dn.Value;
        $MatchingSectionKeys = $Value.Keys | Where-Object { $_ -like $dnPath.Section }

        foreach ($SectionKey in $MatchingSectionKeys) {
            $Section = $Value[$SectionKey];
            if ($dnPath.PathType -eq [ItemType]::Section) {
                ndni -it ([ItemType]::Section) -k $SectionKey -p $SectionKey -v $Section                    
            }
            else {
                $MatchingItemKeys = $Section.Keys | Where-Object { $_ -like $dnPath.Item }
                foreach ($ItemKey in $MatchingItemKeys) {
                    $Item = $Section[$ItemKey];              
                    if ($dnPath.PathType -eq [ItemType]::Item) {
                        $FullPath = "${SectionKey}/${ItemKey}";
                        ndni -it ([ItemType]::Item) -k $ItemKey -p $FullPath -v $Item                            
                    }
                    else {
                        $MatchingPropertyKeys = $Item.Keys | Where-Object { $_ -like $dnPath.Property }
                        foreach ($PropertyKey in $MatchingPropertyKeys) {
                            $Property = $Item[$PropertyKey];
                            $FullPath = "${SectionKey}/${ItemKey}/${PropertyKey}";
                            ndni -it ([ItemType]::Property) -k $PropertyKey -p $FullPath -v $Property
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

Export-ModuleMember -Function *
Export-ModuleMember -Alias *

Write-Host "DataNode imported"