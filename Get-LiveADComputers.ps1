$OU = Read-Host  -Prompt "Enter OU Filter"
$Computers = Get-ADComputer -filter {Enabled -eq $true} | ? {$_.DistinguishedName -like "*$OU*" }
$active = @()
$scriptblock = {
    Param($Computer)
    if (Test-Connection -ComputerName $Computer.DNSHostName -Count 2 -BufferSize 16 -Quiet) {
        Write-Host $Computer.DNSHostName
        $active += $item
    }
}

$Computers | % {Start-Job -ScriptBlock $scriptblock -ArgumentList $_ | Out-Null}
Get-Job | Wait-Job | Receive-Job

$active | measure