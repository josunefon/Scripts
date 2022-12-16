# Title: Import PBIX file to Power BI Service
# Description: Import PBIX file to Power BI Service

# Author: @josunefon
# Reference: https://docs.microsoft.com/en-us/powershell/module/powerbi/new-powerbireport?view=powerbi-ps
# Reference: https://docs.microsoft.com/en-us/powershell/module/powerbi/get-powerbiworkspace?view=powerbi-ps
# Reference: https://docs.microsoft.com/en-us/powershell/module/powerbi/get-powerbireport?view=powerbi-ps
# Reference: https://docs.microsoft.com/en-us/powershell/module/powerbi/new-powerbigroup?view=powerbi-ps

Install-Module -Name MicrosoftPowerBIMgmt  

Connect-PowerBIServiceAccount | Out-Null

# update script with workspace and report names
$workspaceName = "XXX"
$reportName = "XXX"
# update script with file path to your PBIX file
$pbixFilePath = "C:\Users\XXX\Downloads\MercuryDashboard.pbix"

$workspace = Get-PowerBIWorkspace -Name $workspaceName
# check if workspace exists
if($workspace) {
    Write-Host "The workspace named $workspaceName already exists"
} else {
    Write-Host "Creating new workspace named $workspaceName"
    $workspace = New-PowerBIGroup -Name $workspaceName
}
#import the file
try {
    $StartTime = $(get-date)
    $import = New-PowerBIReport -Path $pbixFilePath -Workspace $workspace -ConflictAction CreateOrOverwrite
    $report = Get-PowerBIReport -Workspace $workspace -Name $reportName
    $elapsedTime = $(get-date) - $StartTime
    $totalTime = "{0:mm} min {0:ss} sec'" -f ([datetime]$elapsedTime.Ticks)

    Write-Host ">>>>> The report $($report.Name) was uploaded succesfuly to the $workspaceName workspace in $totalTime" -ForegroundColor Green
    Write-Host ">>>>> Link to access to the report: $($report.WebUrl)" -ForegroundColor Yellow 
}
catch {
    Write-Host ">>>>> An error occurred while uploading the report: $_" -ForegroundColor Red
}

