enum FileFormatEnum {
    PSDataFile;
    Json;
    Xml;
    Csv;
}



function Import-DN {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [FileFormatEnum] $Format = [FileFormatEnum]::PSDataFile
    )
    Begin {
        if (-not (Test-Path -Path $Path)) {
            throw "Path '$Path' doesn't exist."
        }
    }

    Process {
        switch ($Format) {
            { $_ -eq [FileFormatEnum]::PSDataFile } { $dn = Import-PowerShellDataFile -Path $Path ; break; }
            default { throw "File format '$Format' not supported." }
        }
    }

    End {
        $dnWrapper = [PSCustomObject] @{ "Path" = $Path; "HT" = $dn; }
        Write-Output $dnWrapper
    }
}

Set-Alias -Name ipdn -Value Import-DN

function Get-Section {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [PSCustomObject] $dn,
        [Parameter(Mandatory = $true)] [string] $SectionKey,
        [switch] $CreateDefault
    )

    Process {
        [hashtable] $dnht = $dn.HT;
        if ($dnht.ContainsKey($SectionKey)) { $section = $dnht.$SectionKey ; }
        elseif ($CreateDefault) { $section = $dnht = @{} ;}
        else { throw "Section '$SectionKey' not found." }
    }

    End {
        $sectionWrapper = [PSCustomObject]@{ "SectionKey" = $SectionKey; "HT" = $section }
        Write-Output $sectionWrapper
    }
}

Set-Alias -Name gsec -Value Get-Section

function Get-SectionItem {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [PSCustomObject] $Section,
        [string[]] $Keys,
        [switch] $CreateDefault
    )

    Process {
        $sectionHT = $Section.HT

        if (($null -eq $Keys) -or (($Keys -is [array]) -and ($Keys.Count -eq 0))) {
            foreach ($key in $sectionHT.Keys) {
                $item = $sectionHT[$key]
                $itemWrapper = [PSCustomObject] @{ "ItemKey" = $key; "HT" = $item }
                Write-Output $itemWrapper
            }
        }
        else {
            foreach ($key in $Keys) {
                if ($sectionHT.ContainsKey($key)) {
                    $item = $sectionHT[$key]                    
                }
                elseif ($CreateDefault) {
                    $item = $sectionHT[$key] = @{}
                }
                else {
                    throw "Key '$key' is missing in the section $($Section.SectionKey)."
                }

                $itemWrapper = [PSCustomObject] @{ "ItemKey" = $key; "HT" = $item }
                Write-Output $itemWrapper
            }
        }
    }
}

Set-Alias -Name gseci -Value Get-SectionItem

Export-ModuleMember -Function *
Export-ModuleMember -Alias *

Write-Host "DataNode imported"