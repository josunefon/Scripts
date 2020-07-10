<#
    .DESCRIPTION
        Runbook which gets all the ARM resources type quotas and limits in the subscription using the Run As Account (Service Principal) and pushes the data to a Log analytics workspace

    .NOTES
        AUTHOR: Jordi Sune Fontanals
        LASTEDIT: July 09, 2020
#>

#logon
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
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

##Quotas

"-------- Retrieving Compute quotas and usage --------"

$Location = "westeurope"

# Retrieve Compute quota
$ComputeQuota = Get-AzureRmVMUsage -Location $Location | Select-Object -Property Name, CurrentValue, Limit, @{Name="PercQuota";Expression={[int]($_.CurrentValue/$_.Limit * 100)}} 
$ComputeQuota | ForEach-Object {
    if (-not $_.Name.LocalizedValue) {
        $_.Name = $_.Name.Value -creplace '(\B[A-Z])', ' $1'
    }
    else {
        $_.Name = $_.Name.LocalizedValue
    }
} 

$ComputeQuota = $ComputeQuota 

"-------- Retrieving Storage quotas and usage --------"

# Retrieve Storage quota
$StorageQuota = Get-AzureRmStorageUsage -location $Location  | Select-Object -Property Name, CurrentValue, Limit, @{Name="PercQuota";Expression={[int]($_.CurrentValue/$_.Limit * 100)}} 

"-------- Retrieving Network quotas and usage --------"

# Retrieve Network quota
$NetworkQuota = Get-AzureRmNetworkUsage -Location $Location | Select-Object @{ Label="Name"; Expression={ $_.ResourceType } }, CurrentValue, Limit,  @{Name="PercQuota";Expression={[int]($_.CurrentValue/$_.Limit * 100)}} 

# Combine quotas
$AllQuotas = $ComputeQuota + $StorageQuota + $NetworkQuota

""
"-------- Quotas and Usage information received --------"
""
$AllQuotas

# Convert quotas to JSON
$AllQuotas = $AllQuotas | ConvertTo-Json

""
"------------ Pushing Data to Log Analytics ------------"
""

# Push Data to LA
# Replace with your Workspace ID
$CustomerId = "XXXXXXXXXXXX"  

# Replace with your Primary Key
$SharedKey = "XXXXXXXXXXXX"

# Specify the name of the record/table_CL type that you'll be creating
$LogType = "All_QuotasAndLimits"

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

