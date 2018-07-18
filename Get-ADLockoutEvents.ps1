[CmdletBinding()]
param(
    # Export Path for CSV
    [Parameter(Mandatory = $false)]
    [string]
    $ExportPath = $null,
    # Time Frame (Days) for Search
    [Parameter(Mandatory = $true)]
    [int]
    $TimeFrame = $null
)

if ($TimeFrame -lt 1) {
    Write-Error -Message "Please enter a non-zero Time Frame."
    exit
}

if (!(Test-Path -Path (Split-Path -Path $ExportPath -Parent))) {
    New-Item (Split-Path -Path $ExportPath -Parent) -ItemType Directory
}

Import-Module ActiveDirectory

$DomainControllers = Get-ADDomainController -Filter *
$PDCEmulator = ($DomainControllers | Where-Object {$_.OperationMasterRoles -contains "PDCEmulator"})
$arr = @()

foreach ($pdc in $PDCEmulator) {
    $pdcName = $pdc.HostName
    write-host "Checking PDCEmulator: $pdcName"

    $event = Get-WinEvent -ComputerName $pdcName -FilterHashtable @{LogName = 'Security'; Id = 4740; StartTime = (Get-Date).AddDays(($TimeFrame * -1))} | Where-Object {$_.Properties[0].Value -like "*$userName*"} | Select-Object -Property TimeCreated, @{Label = 'UserName'; Expression = {$_.Properties[0].Value}}, @{Label = 'ClientName'; Expression = {$_.Properties[1].Value}}

    if ($ExportPath) {
        $arr += $event
    }
    else {
        $event
    }
}

if ($ExportPath) {
    $arr | export-csv -path $ExportPath -NoTypeInformation
}