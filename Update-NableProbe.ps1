<#
.SYNOPSIS
    Used to update Solarwinds N-Able probe credentials
.DESCRIPTION
    This script can be run through N-Able to force a probe to update the credentials. It
    will stop the Windows Software Probe and Windows Software Probe Maintenance services
    and change the logon type to the credentials provided. It will then create the
    STARTUP.INI configuration file in
    %ProgramFiles(x86)%\N-Able Technologies\Windows Software Probe\bin
    After this it will start up the services.
.EXAMPLE
    PS C:\> Update-NableProbe.ps1 -username <domain\username> -password <password>
    Updates the Probe services to use the username and password provided
.EXAMPLE
    PS C:\> Update-NableProbe.ps1 -username <domain\username> -password <password> -System
    Updates the Probe services to run under the LocalSystem context and updates probe
    credentials in configuration.
.INPUTS
    Username:
        Desired username for the Probe service. Use DOMAIN\USERNAME format.
    Password:
        Desired password for the Probe service.
    -System:
        Optional parameter to set the services to run as System instead of passing the
        probe credentials to the services.
.NOTES
    Not sure the difference between using LocalSystem or Credentials on Probe services
#>
[CmdletBinding()]
param (
    # Username in DOMAIN\Username format
    [Parameter(Mandatory = $true)]
    [string]
    $Username,
    # Password
    [Parameter(Mandatory = $true)]
    [string]
    $Password,
    # System Flag
    [Parameter()]
    [switch]
    $System = $false
)

begin {
    $ConfigText =   "Username=$Username`n" + `
                    "Password=$Password"
    $NablePath = "C:\Program Files (x86)\N-Able Technologies\Windows Software Probe\bin\STARTUP.ini"
    $filter = "name='Windows Software Probe Service' OR " + `
        "name='Windows Software Probe Maintenance Service' OR " + `
        "name='NablePatchRepositoryService'"
    $params = @{
        "Namespace" = "root\CIMV2"
        "Class"     = "Win32_Service"
        "Filter"    = $filter
    }
    $Services = @()

    foreach ($Service in $Filter) {
        $Services += Get-WmiObject @params
    }
}

process {
    try {
        foreach ($Service in $Services) {
            $Service.StopService()
        }
    }
    catch {
        Write-Error -Message "One or more services failed to stop." -ErrorId 1
        exit
    }

    if ($System) {
        foreach ($Service in $Services) {
            $Service.change($null,
                $null,
                $null,
                $null,
                $null,
                $null,
                "LocalSystem",
                "",
                $null,
                $null,
                $null
            )
        }
    } else {
        foreach ($Service in $Services) {
            $Service.change($null,
                $null,
                $null,
                $null,
                $null,
                $null,
                $Username,
                $Password,
                $null,
                $null,
                $null
            )
        }
    }
    Set-Content -Path $NablePath -Value $ConfigText
}

end {
    try {
        foreach ($Service in $Services) {
            $Service.StartService()
        }
    }
    catch {
        Write-Error -Message "Services failed to start." -ErrorId 2
        exit
    }
}