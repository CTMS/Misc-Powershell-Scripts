# Misc-Powershell-Scripts

### Get-ADLockoutEvents
This script will scrape all PDCs for Security Event ID 4740 User Locked Out. Must specify the number of days to search back through. Can specify an export path for a csv.

>>Usage:
>>Get-ADLockoutEvents -TimeFrame _n_ [ -ExportPath c:\path\to\file.csv ]