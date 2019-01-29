$OU = Read-Host  -Prompt "Enter OU Filter"
$Computers = Get-ADComputer -filter {Enabled -eq $true} | ? {$_.DistinguishedName -like "*$OU*" }
$active = @()
foreach ($item in $Computers) {
    if(Test-Connection -ComputerName $item.DNSHostName -BufferSize 16 -Count 2 -Quiet) {
        Write-Host $item.DNSHostName
        $active += $item
    }
}

$active | measure