enum FileFormatEnum {
    psd1;
    json;
    xml;
    csv;
}

enum ItemType {
    Section;
    Item;
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
            $dnWrapper = [PSCustomObject] @{ "Path" = $FileInfo.FullName; "HT" = $dn; }
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

function Get-DnItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [PSCustomObject] $Dn,
        [Parameter(Mandatory = $true)] [string] $Path
    )

    Begin {
        $Parent = Split-Path $Path -Parent;
        $Leaf =  Split-Path $Path -Leaf;
        if ([string]::Empty -eq $Parent) { 
            $Parent = $Leaf ; 
            $Leaf = [string]::Empty 
        }
        if ([string]::Empty -eq $Parent) { throw "Incorrect path '$Path'." }
    }

    Process {
        [hashtable] $DnHT = $dn.HT;
        $MatchingSectionKeys = $DnHT.Keys | Where-Object { $_ -like $Parent }

        foreach ($SectionKey in $MatchingSectionKeys) {
                $Section = $DnHT[$SectionKey];
                if ([string]::Empty -eq $Leaf) {
                    $ItemWrapper = [PSCustomObject] @{"ItemType" = [ItemType]::Section; "Key" = $SectionKey; "HT" = $Section }
                    Write-Output $ItemWrapper                    
                }
                else {
                    $MatchingItemKeys = $Section.Keys | Where-Object { $_ -like $Leaf }
                    foreach ($ItemKey in $MatchingItemKeys) {
                        $Item = $Section[$ItemKey];
                        $ItemWrapper = [PSCustomObject] @{"ItemType" = [ItemType]::Item; "Key" = $ItemKey; "HT" = $Item }
                        Write-Output $ItemWrapper  
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