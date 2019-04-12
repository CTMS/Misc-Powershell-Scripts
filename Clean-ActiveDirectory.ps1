Import-Module ActiveDirectory


###########################################################
#             Active Directory User Functions             #
###########################################################
# Finds all currently Enabled users and searches across all DCs to find Last Logon Date then sorts by Date
# Returns $ActiveUsers array
function Get-ActiveUsers($Username = "*") {

    begin {
        $List = @()
        $LatestLogOn = @()
        $script:ActiveUsers = @()
        Write-Host -ForegroundColor Green "Searching across all Replica Servers for Active Users...`n"
    }

    process {
        (Get-ADDomain).ReplicaDirectoryServers | Sort-Object | % {
            $DC = $_
            Write-Host -ForegroundColor Green "Reading $DC"
            $List += Get-ADUser -Server $_ -Filter {samaccountname -like $Username -and Enabled -eq $true} -Properties lastlogon | ? {($_.distinguishedname -notlike '*CN=Users*') -and ($_.distinguishedname -notlike '*Builtin*')} | Select-Object name, @{n = 'Username'; e = {$_.samaccountname}}, LastLogon, @{n = 'DC'; e = {$DC}}, @{n = 'OU' ; e = {($_.distinguishedname -split ",", 2)[1]}}
        }
        Write-Host -ForegroundColor Green "`nSorting for most recent lastlogon"
        $List | Group-Object -Property 'Username' | % {
            $LatestLogOn += ($_.Group | Sort-Object -prop lastlogon -Descending)[0]
        }
        $script:ActiveUsers += $LatestLogOn | Sort-object -prop Lastlogon -Descending | Select-Object 'Username', 'name', 'OU', 'DC', @{n = 'LastLogonDate'; e = {[datetime]::FromFileTime($_.lastlogon)}}, lastlogon
    }

    end {
        $List.Clear()
        $LatestLogOn.Clear()
        $script:RanActive = $true
    }
}

# Find all Disabled Accounts and move to Disabled OU
# Returns $DisabledUsers array
function Get-DisabledUsers () {
    Begin {
        Write-Host -ForegroundColor Green "Starting search for all disabled users..."
        $script:DisabledUsers = @()
    }

    Process {
        try {
            $script:DisabledUsers += Get-ADUser -Filter {Enabled -eq $false} | Select-Object name, @{n = 'Username' ; e = {$_.samaccountname}}, @{n = 'OU' ; e = {($_.distinguishedname -split ",", 2)[1]}} | Sort-Object -prop OU
        }
        catch {
            Write-Host -BackgroundColor Red "Error: $($_.Exception)"
            Break
        }
    }

    End {
        if ($?) {
            Write-Host -ForegroundColor Green "Completed Successfully."
            $script:RanDisabled = $true
        }
    }
}

# Moves all users in $DisabledUsers into the Disabled Users OU or an OU provided by user
function Move-DisabledUsers {
    [CmdletBinding()]
    param (
        # Disabled OU
        [Parameter(mandatory = $False)]
        [String]
        $DisabledOU
    )

    begin {
        Write-Host -ForegroundColor Green "Searching for disabled users OU..."
    }

    process {
        try {
            if ($DisabledOU = "") {
                Write-Host -ForegroundColor Red "No DisabledOU specified. Searching for Terminated or Disabled Users OU..."
                $DisabledOU = Get-ADOrganizationalUnit -filter {Name -like "Disabled Users" -or Name -like "Terminated Users"}
            } else {
                $DisabledOU = Get-ADOrganizationalUnit -Filter {Name -eq $DisabledOU}
            }
            if ($DisabledOU = "") {
                Write-Host -ForegroundColor Red "Could not find a disabled or temrinated users OU. Please create one or specify an OU."
                return
            }
        }
        catch {

        }
    }

    end {
    }
}

function Disable-InactiveUsers($inactivePeriod = 90) {
    Begin {
        $InactiveDate = (Get-Date).Adddays( - ($inactivePeriod))
        $Results = @()
        Write-Host -ForegroundColor Green "Disabling users who have been inactive for over $inactivePeriod Days..."
        $Results += $script:ActiveUsers | ? {$_.lastlogon -lt $InactiveDate.ToFileTimeUtc()}
    }
    Process {
        Try {
            ForEach ($Item in $Results) {
                Disable-ADAccount -Identity $Item.Username
                Write-Host "$($Item.Username) - Disabled"
            }
        }
        Catch {
            Write-Host -BackgroundColor Red "Error: $($_.Exception)"
            Break
        }
    }
    End {
        If ($?) {
            Write-Host 'Completed Successfully.'
            Write-Host ' '
        }
    }
}

function Get-InactiveADComputers($inactivePeriod = 90) {
    Begin {
        $InactiveDate = (Get-Date).Adddays( - ($inactivePeriod))
        $List = @()
        $LatestLogOn = @()
        $script:InactivePCs = @()
        Write-Host -ForegroundColor Green "Searching across all Replica Servers for Inactive Domain Computers...`n"
    }
    Process {
        (Get-ADDomain).ReplicaDirectoryServers | Sort-Object | % {
            $DC = $_
            Write-Host -ForegroundColor Green "Reading $DC"
            $List += Get-ADComputer -Server $_ -Filter {OperatingSystem -notlike "*server*" -and Enabled -eq $true} -Properties lastlogon | Select-Object name, LastLogon, @{n = 'DC'; e = {$DC}}
        }
        Write-Host -ForegroundColor Green "`nSorting for most recent lastlogon"
        $List | Group-Object -Property 'name' | % {
            $LatestLogOn += ($_.Group | Sort-Object -prop lastlogon -Descending)[0]
        }
        $script:InactivePCs += $LatestLogOn | ? {$_.lastlogon -lt $InactiveDate.ToFileTimeUtc()} | Sort-object -prop Lastlogon -Descending | Select-Object 'name', 'DC', @{n = 'LastLogonDate'; e = {[datetime]::FromFileTime($_.lastlogon)}}, lastlogon
    }
    End {
        $List.Clear()
        $LatestLogOn.Clear()
        $script:RanInactivePCs = $true
    }
}

function Disable-InactiveADComputers($inactivePeriod = 90) {
    Begin {

    }
    Process {

    }
    End {

    }
}

##############################################
#      Support functions for Program         #
##############################################
# Creates Reports of Get function results in CSV format
Function Export-Report {
    [CmdletBinding()]
    param (
        # Report Path
        [Parameter(Mandatory = $false)]
        [String]
        $ReportFilePathRoot = "C:\Logs\Clean-ActiveDirectory"
    )


    Begin {
        Write-Host "Creating requested Reports in specified path [$ReportFilePathRoot]..."
        $ReportType = @()
        if ($script:RanActive) {
            $ReportType += "ActiveUsers"
        }
        if ($script:RanDisabled) {
            $ReportType += "DisabledUsers"
        }
        if ($script:RanInactivePCs) {
            $ReportType += "InactivePCs"
        }
    }

    Process {
        Try {
            if (!(Test-Path $ReportFilePathRoot)) {
                New-Item -path $ReportFilePathRoot -Type Directory
            }

            if ($ReportType -eq $null) {
                Write-Host -ForegroundColor Red "No Reports ran."
            }
            #Check file path to ensure correct
            foreach ($Report in $ReportType) {
                $ReportFilePath = Join-Path -Path $ReportFilePathRoot -ChildPath "\$Report-$([DateTime]::Now.ToString("yyyyMMdd-HHmmss")).csv"
                Write-Host -ForegroundColor Green "Exporting $Report report to $ReportFilePath"
                switch ($Report) {
                    "ActiveUsers" {
                        $script:ActiveUsers | Export-Csv $ReportFilePath -NoTypeInformation -Force
                    }
                    "DisabledUsers" {
                        $script:DisabledUsers | Export-Csv $ReportFilePath -NoTypeInformation -Force
                    }
                    "InactivePCs" {
                        $script:InactivePCs | Export-Csv $ReportFilePath -NoTypeInformation -Force
                    }
                    Default {
                        Write-Host -ForegroundColor Red "No Reports ran."
                    }
                }
            }
        }
        Catch {
            Write-Host -BackgroundColor Red "Error: $($_.Exception)"
            Break
        }
    }

    End {
        If ($?) {
            Write-Host -ForegroundColor Green "Completed Reports Successfully.`n"
        }
    }
}

function Show-Menu {
    Write-Host -ForegroundColor Green "`t[1] Find Active Users"
    Write-Host -ForegroundColor Green "`t[2] Find Disabled Users"
    Write-Host -ForegroundColor Green "`t[3] Find Inactive PCs"
    Write-Host -ForegroundColor Green "`t[4] Move Disabled Users"
    Write-Host -ForegroundColor Green "`t[5] Disable Inactive Users"
    Write-Host -ForegroundColor Green "`t[6] Disable Inactive PCs"
    Write-Host -ForegroundColor Green "`t[9] Export Reports"
    Write-Host -ForegroundColor Red "`t[0] Exit"
}

###################################
#         Main Function           #
###################################
Clear-Host
Write-Host -ForegroundColor Yellow "Initializing Scripts...`n"
Write-Host -ForegroundColor Yellow "Welcome to Active Directory Cleanup!`nBrought to you by the awesome Maria with CTMS :)`n"
Write-Host -ForegroundColor Yellow "Please select an option:`n"
do {
    Show-Menu
    $Selection = Read-Host -Prompt "Enter Selection"
    Clear-Host

    switch ($Selection) {
        "0" {
            Write-Host -ForegroundColor Green "Exiting Program."
            exit
        }
        "1" {
            try {
                Write-Host -ForegroundColor Green "Starting Get-ActiveUsers Script..."
                Get-ActiveUsers
                $output = Read-Host -Prompt "`nWould you like to write results to console? [y/N]"
                if ($output -eq "y") {
                    $script:ActiveUsers | Select-Object 'Username', 'OU', 'LastLogonDate'
                }
                else {
                    Write-Host -ForegroundColor Green "Returning to main menu."
                }
            }
            catch {
                Write-Host -BackgroundColor Red "Unknown Error occured with Get-ActiveUsers script."
            }
        }
        "2" {
            try {
                Write-Host -ForegroundColor Green "Starting Get-DisabledUsers Script..."
                Get-DisabledUsers
                $output = Read-Host -Prompt "`nWould you like to write results to console? [y/N]"
                if ($output -eq "y") {
                    $script:DisabledUsers
                }
                else {
                    Write-Host -ForegroundColor Green "Returning to main menu."
                }
            }
            catch {
                Write-Host -BackgroundColor Red "Unknown Error occured with Get-DisabledUsers script."
            }
        }
        "3" {
            Write-Host -ForegroundColor Red "This feature is not fully implemented yet."
            try {
                Write-Host -ForegroundColor Green "Starting Get-InactiveADComputers Script..."
                Get-InactiveADComputers
                $output = Read-Host -Prompt "`nWould you like to write results to console? [y/N]"
                if ($output -eq "y") {
                    $script:InactivePCs | Select-Object 'Name', 'DC', 'LastLogonDate'
                }
                else {
                    Write-Host -ForegroundColor Green "Returning to main menu."
                }
            }
            catch {
                Write-Host -BackgroundColor Red "Unknown Error occured with Get-ActiveUsers script."
            }
        }
        "4" {
            Write-Host -ForegroundColor Red "This feature is not fully implemented yet."
        }
        "5" {
            Write-Host -ForegroundColor Red "This feature is not fully implemented yet."
            # if ($script:RanDisabled) {
            #     Write-Host -BackgroundColor Red "Are you sure you want to do this? This will bulk disable users."
            #     $confirmOption = Read-Host -Prompt "Type DISABLE USERS to continue"
            #     if ($confirmOption -ceq "DISABLE USERS") {
            #         Write-Host -ForegroundColor Green "Disabling inactive users...`n"
            #         do {
            #             try {
            #                 [ValidatePattern("^[0-9]+$|0")]$Days = Read-Host -Prompt "Please enter number of days for inactivity (Ex 90)"
            #                 $ValidateCheck = $true
            #             }
            #             catch {
            #                 Write-Host -BackgroundColor Red "Please enter a valid number."
            #                 $ValidateCheck = $false
            #             }
            #         } until ($ValidateCheck)
            #         Disable-InactiveUsers -inactivePeriod $Days
            #     }
            #     else {
            #         Write-Host -ForegroundColor Red "Confirmation prompt failed. Returning to main menu."
            #     }
            # }
            # else {
            #     Write-Host -ForegroundColor Red "Please run option 2 first."
            # }
        }
        "6" {
            Write-Host -ForegroundColor Red "This feature is not fully implemented yet."
        }
        "9" {
            Write-Host -ForegroundColor Green "Exporting Results to CSV."
            Export-Report
        }
        Default {
            Write-Host -ForegroundColor Red "Please make a valid Selection."
        }
    }
} until ($Selection -eq "0")