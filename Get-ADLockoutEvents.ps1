[CmdletBinding()]
param(
    # Export Path for CSV
    [Parameter(Mandatory = $false)]
    [string]
    $exportPath = $null,
    # Time Frame (Days) for Search
    [Parameter(Mandatory = $true)]
    [int]
    $timeFrame = $null
)

if ($timeFrame -lt 1) {
    Write-Error -Message "Please enter a non-zero Time Frame."
    exit
}

if (!(Test-Path -Path (Split-Path -Path $exportPath -Parent))) {
    New-Item (Split-Path -Path $exportPath -Parent) -ItemType Directory
}

Import-Module ActiveDirectory

$DomainControllers = Get-ADDomainController -Filter *
$PDCEmulator = ($DomainControllers | Where-Object {$_.OperationMasterRoles -contains "PDCEmulator"})
$arr = @()

foreach ($pdc in $PDCEmulator) {
    $pdcName = $pdc.HostName
    write-host "Checking PDCEmulator: $pdcName"

    $event = Get-WinEvent -ComputerName $pdcName -FilterHashtable @{LogName = 'Security'; Id = 4740; StartTime = (Get-Date).AddDays(($timeFrame * -1))} | Where-Object {$_.Properties[0].Value -like "*$userName*"} | Select-Object -Property TimeCreated, @{Label = 'UserName'; Expression = {$_.Properties[0].Value}}, @{Label = 'ClientName'; Expression = {$_.Properties[1].Value}}

    if ($exportPath) {
        $arr += $event
    }
    else {
        $event
    }
}

if ($exportPath) {
    $arr | export-csv -path $exportPath -NoTypeInformation
}