<#
.SYNOPSIS
Runs a HTTP trigger for the function App
.DESCRIPTION
Runs a HTTP trigger for the function App
.PARAMETER timer
Mandatory. Schedule to run the function App
#>

Import-Module -Name Az.Accounts -Force
Import-Module -Name Az.Websites -Force
Import-Module -Name Az.Resources -Force

# Input bindings are passed in via param block.
#param($Timer)

Set-AzContext -Subscription "XXXXXXXXX"

$FunctionAppName = "XXXX"
$GroupName = "YYYY"
$TriggerNames = @("OnDemandAdvisorRecommendationsUpdate","OnDemandASCAlertsUpdate","OnDemandASCAssessmentsMetadataUpdate","OnDemandASCAssessmentsUpdate","OnDemandASCSecureScoreControlsUpdate","OnDemandASCSecureScoreUpdate","OnDemandEntityUpdate","OnDemandKeyVaultUpdate","OnDemandNicUpdate","OnDemandPolicyDefinitionsUpdate","OnDemandPolicySetDefinitionsUpdate","OnDemandPricingUpdate","OnDemandResourcesUpdate","OnDemandSubAssessmentUpdate","OnDemandVirtualMachinePatchUpdate","OnDemandVirtualMachineUpdate","OnDemandPolicyStatesUpdate")
$FunctionApp = Get-AzWebApp -ResourceGroupName $GroupName -Name $FunctionAppName

foreach ($TriggerName in $TriggerNames) {
    $funcKey = (Invoke-AzResourceAction `
        -Action listKeys `
        -ResourceType 'Microsoft.Web/sites/functions/' `
        -ResourceGroupName $GroupName `
        -ResourceName "$FunctionAppName/$TriggerName" `
        -Force).default
    $invokeurl = "https://"+$FunctionApp.EnabledHostNames[0]+"/api/"+$TriggerName+"?code="+$funcKey
    Write-Verbose "Processing: $TriggerName for $FunctionAppName on $($FunctionApp.EnabledHostNames[0])" -verbose
    $headers = @{
        "Content-Type" = "application/json"
    }

    $resp = invoke-webrequest -method GET -uri $invokeurl -header $headers

    if ($triggerName -eq "OnDemandResourcesUpdate") {
            start-sleep -Seconds 3600    
        }else{
            start-sleep -Seconds 2700
        }
}


