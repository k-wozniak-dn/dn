#region const
enum ItemType {
    dn;
    s;
    i;
    p;
    eos;
    eoi;
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
            ($_ -eq [ItemType]::p) -or
            ($_ -eq [ItemType]::eos) -or
            ($_ -eq [ItemType]::eoi)
        })] $ItemType = [ItemType]::p,

        [Parameter(Mandatory = $false)] [Alias("k")] [string] $Key = $null,

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
        elseif (
            ($ItemType -eq [ItemType]::i) -or 
            ($ItemType -eq [ItemType]::s) -or 
            ($ItemType -eq [ItemType]::dn) -or
            ($ItemType -eq [ItemType]::eos) -or
            ($ItemType -eq [ItemType]::eoi)
            ) 
        {
            if (-not ($Value -is [hashtable])) { throw "Incorrect Value type." }
        }      
        else { throw "Unhandled ItemType." }
    }

    Process {
    }

    End {
        Write-Output [PSCustomObject] @{ 
            it = $ItemType; 
            k = $Key;
            p = $Path; 
            v = $Value;
            vt = ($Value.GetType().ToString() -split "\.") | Select-Object -Last 1
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
                    $dn = Import-PowerShellDataFile -Path $FileInfo.FullName -SkipLimitCheck ;
                    break; 
                }
                default { throw "File format '$ext' not supported." }
            }
            ndni -it ([ItemType]::dn) -k $null -p $FileInfo.FullName -v $dn;
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
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $false)] [switch] $AddParents
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
                if ($AddParents) { ndni -it ([ItemType]::s) -k $SectionKey -p $SectionKey -v $Section ; }
                $MatchingItemKeys = $Section.Keys | Where-Object { $_ -like $dnPath.ItemPart }
                foreach ($ItemKey in $MatchingItemKeys) {
                    $ItemPath = "${SectionKey}${PathDelimiter}${ItemKey}";                    
                    $Item = $Section[$ItemKey];              
                    if ($dnPath.PathType -eq [ItemType]::i) {
                        ndni -it ([ItemType]::i) -k $ItemKey -p $ItemPath -v $Item                            
                    }
                    else {
                        if ($AddParents) { ndni -it ([ItemType]::i) -k $ItemKey -p $ItemPath -v $Item  }
                        $MatchingPropertyKeys = $Item.Keys | Where-Object { $_ -like $dnPath.PropertyPart }
                        foreach ($PropertyKey in $MatchingPropertyKeys) {
                            $PropertyPath = "${SectionKey}${PathDelimiter}${ItemKey}${PathDelimiter}${PropertyKey}";                            
                            $Property = $Item[$PropertyKey];
                            ndni -it ([ItemType]::p) -k $PropertyKey -p $PropertyPath -v $Property
                        }
                    }
                    if ($AddParents) { ndni -it ([ItemType]::eoi) -k $ItemKey -p $ItemPath -v $Item  }
                }
            }
            if ($AddParents) { ndni -it ([ItemType]::eos) -k $SectionKey -p $SectionKey -v $Section  }
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
function Export-Dn {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [PSCustomObject] $DnItem,
        [Parameter(Mandatory = $true)] [string] $Path
    )

    try {
        if ($DnItem.it -ne [ItemType]::dn) { throw "Only DataNode can be exported." }
        $ext = [System.IO.Path]::GetExtension($Path);
        switch ($ext) {
            { $_ -eq ("." + [FileFormatEnum]::psd1) } { 
                $output = "@{`n";
                gdni -Dn $DnItem -Path "*${PathDelimiter}*${PathDelimiter}*" -AddParents |
                ForEach-Object {
                    $dni = $_;
                    switch ($dni.it) {
                        { $_ -eq [ItemType]::s } { $output += "`t$($dni.k) = @{`n"; }
                        { $_ -eq [ItemType]::i } { $output += "`t`t$($dni.k) = @{`n"; }
                        { $_ -eq [ItemType]::p } { 
                            $textDelimiter = $dni.vt -eq [ValueType]::String ? "'" : ""
                            $output += "`t`t`t$($dni.k) = ${textDelimiter}$($dni.v)${textDelimiter};`n"; 
                        }
                        { $_ -eq [ItemType]::eos } { $output += "`t};`n"; }
                        { $_ -eq [ItemType]::eoi } { $output += "`t`t};`n"; }
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

    Set-Content -Path $Path -Value $output;
    Get-Item -Path $Path;
}

Set-Alias -Name exdn -Value Export-Dn
#endregion

Export-ModuleMember -Function *
Export-ModuleMember -Alias *

Write-Host "DataNode imported"