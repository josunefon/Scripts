<#
    .DESCRIPTION
    Script to retrieve all teh SPNs with expired credentials
    
    .NOTES
        AUTHOR: Jordi Sune Fontanals
        LASTEDIT: March 2, 2022
#>

$Watch = [System.Diagnostics.Stopwatch]::StartNew()

Connect-Azaccount

[datetime]$currentDate = Get-date -Format "dd/MM/yyyy"
$totalSPNS = (Get-AzADServicePrincipal).count
write-host "SPN to review: " $totalSPNS
$allspn = Get-AzADServicePrincipal #-first 30
$cred= @()
$allspn| Foreach-Object {
    $spn = $_
    Get-AzADSpCredential -id $spn.id | Where-Object {[DateTime]::ParseExact($_.EndDate.Split(" ")[0], "dd/MM/yyyy", $null) -lt $currentDate} | Foreach-Object {
        write-host "Expired credentials found for SPN: " $spn.displayName
        $aux = New-Object -TypeName PSObject -Property @{
                DisplayName = $spn.DisplayName
                AppId = $spn.ApplicationId
                ObjectId = $spn.Id
                KeyId = $_.KeyId
                StartDate = $_.StartDate
                EndDate = $_.EndDate
            }
            #write-host $aux | ConvertTo-Json
        $cred += $aux
    }
    $totalSPNS = $totalSPNS - 1
    write-host "Remaining SPNs: " $totalSPNS
}

write-host "Total expired credentials: " $cred.count
$cred > "SPNExpiredCredentials.json"

Write-Host -foregroundcolor Yellow "[SPN Secret Expiration check] Took $($Watch.Elapsed.TotalMinutes) minutes"
write-host "_________________________________"

