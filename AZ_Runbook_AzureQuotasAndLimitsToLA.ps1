
<#
    .DESCRIPTION
    Runbook for getting all the ARM resources type quotas and limits in all subscriptions using the Run As Account (Service Principal) and pushes the data to a Log analytics workspace
        -	Loop all subscriptions that the SP has access to
        -	Retrieve quotas from all regions that have resources deployed (resource graph to the rescue!)
        -	Includes role assignments
        -	Add new columns to help with data manipulation:
                - "QuotaType"
                - "SubscriptionId"
                - "SubscriptionName"
                - "Location"
                
     Required Az Modules:
        -	Az.Accounts
        -	Az.Compute
        -	Az.Network
        -	Az.ResourceGraph
        -	Az.Resources
        -	Az.Storage
    The SP requires Directory.Read.All in AAD Graph API due to way the Get-AzRoleAssignment works (https://github.com/Azure/azure-powershell/issues/13573)

    
    .NOTES
        AUTHOR: Jordi Sune Fontanals & Luis Arnauth
        LASTEDIT: March 15, 2021
#>

#logon
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

$subscriptions = Get-AzSubscription
$AllQuotas = @()
$RoleAssignmentsQuotaValue = 2000

foreach ($subscription in $subscriptions) {
    $null = Set-AzContext -SubscriptionId $subscription.id
    $locations = Search-AzGraph -Query "Resources | where subscriptionId == '$($subscription.Id)' | distinct location"
    foreach ($location in $locations.location) {
        if ($location -eq "global") {
            continue
        }
        "-------- Retrieving Compute quotas and usage for $($location) in $($subscription.Name) --------"
        $ComputeQuota = Get-AzVMUsage -Location $Location | Select-Object -Property Name, CurrentValue, Limit, @{Name="PercQuota";Expression={[int]($_.CurrentValue/$_.Limit * 100)}}    
        $ComputeQuota | ForEach-Object {
            if (-not $_.Name.LocalizedValue) {
                $_.Name = $_.Name.Value -creplace '(\B[A-Z])', ' $1'
            }
            else {
                $_.Name = $_.Name.LocalizedValue
            }
        }
        $ComputeQuota | Add-Member -NotePropertyName "QuotaType" -NotePropertyValue "ComputeQuota"
        $ComputeQuota | Add-Member -NotePropertyName "SubscriptionId" -NotePropertyValue $($subscription.Id)
        $ComputeQuota | Add-Member -NotePropertyName "SubscriptionName" -NotePropertyValue $($subscription.Name)
        $ComputeQuota | Add-Member -NotePropertyName "Location" -NotePropertyValue $($location)
        $ComputeQuota = $ComputeQuota
        $AllQuotas += $ComputeQuota

        "-------- Retrieving Storage quotas and usage for $($location) in $($subscription.Name) --------"
        $StorageQuota = Get-AzStorageUsage -location $Location  | Select-Object -Property Name, CurrentValue, Limit, @{Name="PercQuota";Expression={[int]($_.CurrentValue/$_.Limit * 100)}} 
        $StorageQuota | Add-Member -NotePropertyName "QuotaType" -NotePropertyValue "StorageQuota"
        $StorageQuota | Add-Member -NotePropertyName "SubscriptionId" -NotePropertyValue $($subscription.Id)
        $StorageQuota | Add-Member -NotePropertyName "SubscriptionName" -NotePropertyValue $($subscription.Name)
        $StorageQuota | Add-Member -NotePropertyName "Location" -NotePropertyValue $($location)
        $AllQuotas += $StorageQuota

        "-------- Retrieving Network quotas and usage for $($location) in $($subscription.Name) --------"
        $NetworkQuota = Get-AzNetworkUsage -Location $Location | Select-Object @{ Label="Name"; Expression={ $_.ResourceType } }, CurrentValue, Limit,  @{Name="PercQuota";Expression={[int]($_.CurrentValue/$_.Limit * 100)}} 
        $NetworkQuota | Add-Member -NotePropertyName "QuotaType" -NotePropertyValue "NetworkQuota"
        $NetworkQuota | Add-Member -NotePropertyName "SubscriptionId" -NotePropertyValue $($subscription.Id)
        $NetworkQuota | Add-Member -NotePropertyName "SubscriptionName" -NotePropertyValue $($subscription.Name)
        $NetworkQuota | Add-Member -NotePropertyName "Location" -NotePropertyValue $($location)
        $AllQuotas += $NetworkQuota
    }
    "-------- Retrieving Role Assignments usage for $($subscription.Name) --------"
    $RoleAssignments = (Get-AzRoleAssignment -Scope "/subscriptions/$($subscription.Id)" | Where-Object {$_.Scope -Like "/subscriptions/$($subscription.Id)*"}).count
    [int]$PercQuota = $roleAssignments/$RoleAssignmentsQuotaValue*100
    $RoleAssignmentsQuota = New-Object -TypeName psobject
    $RoleAssignmentsQuota | Add-Member -NotePropertyName "Name" -NotePropertyValue "Role Assignments"
    $RoleAssignmentsQuota | Add-Member -NotePropertyName "CurrentValue" -NotePropertyValue $roleAssignments
    $RoleAssignmentsQuota | Add-Member -NotePropertyName "Limit" -NotePropertyValue $RoleAssignmentsQuotaValue
    $RoleAssignmentsQuota | Add-Member -NotePropertyName "PercQuota" -NotePropertyValue $PercQuota
    $RoleAssignmentsQuota | Add-Member -NotePropertyName "QuotaType" -NotePropertyValue "RoleAssignmentsQuota"
    $RoleAssignmentsQuota | Add-Member -NotePropertyName "SubscriptionId" -NotePropertyValue $($subscription.Id)
    $RoleAssignmentsQuota | Add-Member -NotePropertyName "SubscriptionName" -NotePropertyValue $($subscription.Name)
    $RoleAssignmentsQuota | Add-Member -NotePropertyName "Location" -NotePropertyValue $($location)
    $AllQuotas += $RoleAssignmentsQuota
}

# Convert quotas to JSON
$AllQuotas = $AllQuotas | ConvertTo-Json

""
"------------ Pushing Data to Log Analytics ------------"
""

$logAnalyticsCred = Get-AutomationPSCredential -Name ' log-azr-prd-001'

# Push Data to LA
# Replace with your Workspace ID
$CustomerId = $logAnalyticsCred.UserName 

# Replace with your Primary Key
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($logAnalyticsCred.Password)
$SharedKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

# Specify the name of the record/table_CL type that you'll be creating
$LogType = "ccoeQuotasAndLimits"

# You can use an optional field to specify the timestamp from the data. If the time field is not specified, Azure Monitor assumes the time is the message ingestion time
$TimeStampField = ""

$json = $AllQuotas

# Create the function to create the authorization signature
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}

# Create the function to create and post the request
Function Post-LogAnalyticsData($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode

}

# Submit the data to the API endpoint
Post-LogAnalyticsData -customerId $customerId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($json)) -logType $logType  
