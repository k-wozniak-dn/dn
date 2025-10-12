
#Requires -Modules DataNode

function Start-Build {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [PSCustomObject] $ConfigDN
    )

    Begin {
        [PSCustomObject] $section = Get-Section -dn $ConfigDN -SectionKey "project";
        if ($null -eq $section) { throw "Section 'project' not found." }
    }

    Process {
        Get-SectionItem -Section $section |
        ForEach-Object {
            $params = @("build", $_.HT.path, "--configuration", "Release");
            dotnet @params;
        } 
    }

    End {
        # $sectionWrapper = [PSCustomObject]@{ "SectionKey" = $SectionKey; "HT" = $section }
        # Write-Output $sectionWrapper
    }
}

Export-ModuleMember -Function *
Export-ModuleMember -Alias *

Write-Host "Pipeline imported"