<#
.SYNOPSIS
  Script to automate Skype onprem user move to Teams only for large batch migrations (several thousand users in a batch). 
  Features:
  	- Move speed 10-20x faster due to parallel processing
	    The script works 10-20 times faster than a traditional one as it executes user moves in parallel as much as possible (but not exceeding the cloud threshold of max user moves at a time)
	- Automatic re-try logic for failed to move users
	    For users who failed to move initially (e.g. throttling or some other error) the script will automatically retry them (3 times by default) so you don't have to do it manually
	- Move prerequisite checks
	    Sort out and report users who don't meet the prerequisites so that the identified missing prerequisites can be corrected for those users.
	- Rich reporting capabilities
        Script provides comprehensive reporting for every action or check and will report each user processing and results at various stages of migration and also a summary of the results, including how many were moved successfully, how many failed to migrate (grouped by the error message) how many were retried, etc. which is really helpful during the migration to identify bottlenecks and address issues at an early stage
   Limitations:
    - The script currently does not support the move of Skype onprem users enabled for EV as well as enabling EV capabilities in Teams for moved users. This is currently in testing and will be added soon with a new version of the script.

.DESCRIPTION
  The script will process all users from the input CSV file (InputUsersCsv parameter). There are 2 main parts of the script:
  1. Check pre-requisites before the move (Use SkipAllPrerequisiteChecks parameter to skip this step). Below are the conditions that will trigger user to NOT be moved to Teams only (checks are performed in the order below):
    - User does not exist onprem (onprem Get-CsUser fails)
    - User is located in a particular OU that should be skipped (if user is in the OU specified in $OuToSkip, the acccount won't be moved to Teams)
    - User is already in o365
    - Either LineURI attribute is populated onprem or EnterpriseVoiceEnabled onprem attribute is set to True (the script will be updated later to support EV user moves)
    - User is not licensed for Skype and/or Teams in o365
  2. Move to Teams only
    - Users will be moved in parallel batches (works 10-20 times faster than moving users one by one)
    - Users initially failed to move will be retried 3 times by default

.PARAMETER InputUsersCsv
    File with users to be moved. "UPN" (without double quotes) must be the first line (header), than each user's UPN value on a separate line
.PARAMETER ForceSkypeEvUsersToTeamsNoEV
    By default the script will not move Skype onprem users enabled for Enterprise Voice. If this parameter is used the script will forcefully move those users to Teams without EV functionality
.PARAMETER SkipAllPrerequisiteChecks
    Will not perform any pre-requisite checks and try to move all users specified in the input file
.PARAMETER OuToSkip
    Users located in this OU in local Active Directory will not be moved to Teams. Can be full OU DN or just a part of it. Wildcards are allowed.

.INPUTS
  A CSV file with user UPNs to be moved from Skype onprem to Teams only. "UPN" (without double quotes) must be the first line (header), than each user's UPN value on a separate line

.OUTPUTS
  Log file to track the progress and results of the move. The file will be created in the same directory as the input csv file (specified in inputUsersCsv parameter) and have a DateTime stamp appended to its name: "$ScriptWorkDir\MoveResults$(Get-Date -Format '_MM-dd-yyyy_HH-mm-ss').txt", e.g.: "c:\scripts\teamsmove\MoveResults_02-09-2021_17-15-01.txt"
  Log file structure. Use Excel to easily analyze:
  - Individual user entries:
      Date/Time, Operation, UPN, Result, Result Details
      e.g.:
        02/16/2021 22:26:23,PrerequisiteCheck,Testmove3@contoso.com,ReadyToMove,User is ready to be moved to Teams
        02/16/2021 22:26:24,PrerequisiteCheck,Testmove4@contoso.com,Skipped,User not found
  - Summary entries:
      Date/Time, Summary Operation, Succeeded #, Failed #, Time Taken
      e.g.:
        02/16/2021 22:26:25,PrereqSummary,Ready to move: 4,Pre-reqs not met: 3,Time taken: 00:00:04.3187720
        02/16/2021 22:26:34,MoveSummary,Moved Successfully: 4,Failed to move: 0,Time taken: 00:00:09.3513578
      
.NOTES
  Version:        1.0
  Author:         ALEXEY SMELOVSKIY
  Creation Date:  2/17/2021
  Purpose/Change: Initial script development
  
.EXAMPLE
The below command will move all users specified in the input csv file bypassing any prerequisite check and will skip (not move) users in "OU=DisabledUsers,DC=contoso,DC=com" Organizational Unit in local Active directory
  C:\scripts\teamsmove\MigrateToTeams.ps1 -inputUsersCsv "C:\scripts\teamsmove\userlist.csv" -OuToSkip "OU=DisabledUsers,DC=contoso,DC=com" -SkipAllPrerequisiteChecks
#>

param 
(
    #Path to CSV file with UPNs of users to migrate to Teams. First line should always be "UPN" (without double quotes)
    [Parameter(Mandatory=$true)]
    [string]$InputUsersCsv, 
    [switch]$ForceSkypeEvUsersToTeamsNoEV,
    [switch]$SkipAllPrerequisiteChecks,
    [string]$OuToSkip
)

#Script working directory. Output log and some temporary files will be stored here. By default - same directory as input csv file withe users
$ScriptWorkDir = Split-Path $InputUsersCsv #$PSScriptRoot

#Log file to track the results of the move
$MoveResultsLog = "$ScriptWorkDir\MoveResults$(Get-Date -Format '_MM-dd-yyyy_HH-mm-ss').txt"

#Cred prompt will only be displayed if $cred is blank (credentials haven't been prompted yet).
If (!($cred)) {$cred = get-credential -Message "Enter the credentials of your Teams/Skype admin in o365"}

#Connect to SfBO/Teams powershell. 
Import-Module MicrosoftTeams
Connect-MicrosoftTeams -Credential $cred

#Number of users to be moved from Skype onprem to Teams only in a single batch in parallel
[int]$ParallelExecutions = 25

#Number of retry cycles for users that initially failed the migration
[int]$RetryCycles = 3

#Import users from CSV file
$InputUsersList = Import-Csv -Path $InputUsersCsv 

#Catch all errors
$ErrorActionPreference = "SilentlyContinue"

#Stores users that met the pre-requisites check
$global:UsersWithPrereqsMet = @()
#Stores users that failed (to be able to re-try them during next cycle)
$RetryUsers = @()

#Check if user has required licenses with the following components enabled: Teams and SfBO 
function UserIsLicensed([string]$UserUpn)
{
$AssignedPlans = (Get-CsOnlineUser $UserUpn).AssignedPlan
$LicArray = @()

foreach ($AssignedPlan in $AssignedPlans)
{
[xml]$xmlAssignedPlan = $AssignedPlan
$AssignedPlanStatus = $xmlAssignedPlan.XmlValueAssignedPlan.Plan.CapabilityStatus
if ($AssignedPlanStatus -eq "Enabled")
    {
    $AssignedPlanName = $xmlAssignedPlan.XmlValueAssignedPlan.Plan.Capability.Capability.Plan
    $LicArray += $AssignedPlanName
    }
}

If ($licArray.Contains("Teams") -and $licArray.Contains("MCOProfessional")) {$CommandResult = "True"} else {$CommandResult = "False"}

return $CommandResult

<#
License names in Get-CsOnlineUser.AssignedPlan:
MCOMEETADD - Audio Conferencing
MCOEV - Phone System
MCOProfessional - Skype Online Plan 2
Teams - Teams
#>
}

Function GetHostedMigrationServiceUrl
{
[string]$TenantIdentity = (Get-CsTenant).Identity
[int]$strStart = $TenantIdentity.IndexOf("lync") + 4 #4 is the length of "lync"
$strLength = $TenantIdentity.Length - $indStart - 12 #12 is the length of "001,DC=local" (tenant id always ends with "001,DC=local")
#"https://admin1a.online.lync.com/HostedMigration/hostedmigrationService.svc"
[string]$HostedMigrationServiceUrl = "https://admin$($TenantIdentity.Substring($indStart,$strLength)).online.lync.com/HostedMigration/hostedmigrationService.svc"
return $HostedMigrationServiceUrl
}

function CheckPrerequisites($UserList)
{
$i = 0
$StartTime = Get-Date
    foreach($user in $UserList)
    {
    #Progress counter
    $i++    
    Write-Host "Checking pre-reqs for: " -NoNewline; Write-Host "$($user.UPN): " -NoNewline -ForegroundColor Cyan
    $timestamp = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
    $GetCsUserError = $null
    $SkypeUser = get-csUser "sip:$($user.UPN)" -ErrorVariable GetCsUserError 
    #If get-csuser fails, throw the error below
    if ($GetCsUserError) 
    {
    $ActionType = "Pre-requisite check"
    $ActionResult = "Skipped"
    $ActionResultDetails = "User not found"
    Write-Host "UserNotFound" -ForegroundColor Red
    }
    else
    {
        #Check if user is in OU that should be skipped (OuToSkip parameter)
        #if (2 -eq 1) - uncomment this line and comment the line below to disable this pre-req check
        if ($SkypeUser.Identity.Parent.ToString() -like $OuToSkip)
        {
        
        $ActionType = "Pre-requisite check"
        $ActionResult = "Skipped"
        $ActionResultDetails = "User is in Skipped OU"
        Write-Host "$ActionResult - $ActionResultDetails" -ForegroundColor Yellow
        }
        else
            {
            #Check if user is already in o365
            #if (2 -eq 1) - uncomment this line and comment the line below to disable this pre-req check
            if ($SkypeUser.HostingProvider -contains "sipfed.online.lync.com")
            {
            $ActionType = "Pre-requisite check"
            $ActionResult = "Skipped"
            $ActionResultDetails = "User is already in the cloud"
            Write-Host "$ActionResult - $ActionResultDetails" -ForegroundColor Yellow
            }
            else
                {
                #Check for EV attributes Onprem - skip user if it is EV enabled onprem or line uri is set
                #if (2 -eq 1) - uncomment this line and comment the line below to disable this pre-req check
                if (($SkypeUser.LineURI -or $SkypeUser.EnterpriseVoiceEnabled) -and (!($ForceSkypeEvUsersToTeamsNoEV)))
                    {
                        $ActionType = "Pre-requisite check"
                        $ActionResult = "Skipped"
                        $ActionResultDetails = "User is either EV enabled onprem or has onprem LineURI"
                        Write-Host "$ActionResult - $ActionResultDetails" -ForegroundColor Yellow
                    }
                else
            
                    {                
                    #Check for required licenses
                    #if (2 -eq 1) - uncomment this line and comment the line below to disable this pre-req check
                    if ((UserIsLicensed($user.UPN)) -ne "True")
                        {
                        $ActionType = "Pre-requisite check"
                        $ActionResult = "Skipped"
                        $ActionResultDetails = "User doesn't have proper licenses assigned"
                        Write-Host "$ActionResult - $ActionResultDetails" -ForegroundColor Yellow
                        }
                    else
                    #Pre-reqs satisfied, prepare for the move
                        {
                        $ActionType = "Pre-requisite check"
                        $ActionResult = "ReadyToMove"
                        $ActionResultDetails = "User is ready to be moved to Teams"
                        Write-Host $ActionResult -ForegroundColor Green
                        $global:UsersWithPrereqsMet += $user

                        }#final else ends
                        }#EV else ends
            }#User already in the cloud else ends
        }#Suspended OU ends
    }#Usernotfound else ends
        "$timestamp,PrerequisiteCheck,$($user.UPN),$ActionResult,$ActionResultDetails" | Out-File $MoveResultsLog -Append
        
        Write-Progress -Activity “Checking Prerequisites - $([math]::Round($i/$InputUsersList.count*100))%” -status “Checking user $($user.UPN)” -PercentComplete ($i/$InputUsersList.count*100)
    }#Foreach end
$EndTime = Get-Date
Write-Host ""
Write-Host "===================================================="
Write-Host "                  Pre-Reqs SUMMARY                  " -BackgroundColor DarkYellow
Write-Host "Ready to move: `t`t $($UsersWithPrereqsMet.Count)" #-ForegroundColor Green
Write-Host "Pre-reqs not met: `t $($UserList.Count - $UsersWithPrereqsMet.Count)" #-ForegroundColor Red
Write-Host "Time taken: `t`t $($EndTime-$StartTime)" #-BackgroundColor Magenta
Write-host "Log file: `t`t`t $MoveResultsLog"
Write-Host "                                                    " -BackgroundColor DarkYellow
Write-Host "===================================================="
Write-Host ""
"$EndTime,PrereqSummary,Ready to move: $($UsersWithPrereqsMet.Count),Pre-reqs not met: $($UserList.Count - $UsersWithPrereqsMet.Count),Time taken: $($EndTime-$StartTime)" | Out-File $MoveResultsLog -Append
}


function BatchMoveUsers($MoveUserList)
{
#Re-create tmp folder
Remove-Item "$ScriptWorkDir\tmp" -Recurse -Force -Confirm:$false | out-null
New-Item -Path "$ScriptWorkDir\tmp" -ItemType "directory" | out-null

#Store start timestamp
$StartTime = Get-Date

#write-host $UserBatch -BackgroundColor Blue
    #Initialize the batch variables
    $currentUserBatch = @()
    $BatchUserCounter = 0
    $CurrentUserCounter = 0
    $Global:RetryUsers = @()

foreach ($user in $MoveUserList)
    {
            #Start batch counters
            $BatchUserCounter++
            $CurrentUserCounter++
            $MoveCsUserResultError = $null
            $currentUserBatch += $user

            #If last batch is less than $ParallelExecutions then we need to split it in smaller batches
            $TotalUsersLeft = $moveuserlist.Count - $CurrentUserCounter + $BatchUserCounter
            
            <#
            write-host "####################################"
            write-host "ParallelExecutions = $ParallelExecutions"
            write-host "TotalUsersLeft = $TotalUsersLeft"
            write-host "CurrentUserCounter = $CurrentUserCounter"
            write-host "BatchUserCounter = $BatchUserCounter"
            write-host "####################################"
            #>

            Write-Progress -Activity “Moving a batch of $BatchUserCounter users - $([math]::Round(($CurrentUserCounter-$BatchUserCounter)/$MoveUserList.count*100))%” -status “Current number of users moved: $($CurrentUserCounter - $BatchUserCounter)” -PercentComplete (($CurrentUserCounter - $BatchUserCounter)/$MoveUserList.count*100)

            if (($BatchUserCounter -eq $ParallelExecutions) -or (($BatchUserCounter -lt $ParallelExecutions) -and ($currentUserBatch.Count -ge $TotalUsersLeft))) #(($TotalUsersLeft -le $ParallelExecutions) -and ($BatchUserCounter -eq $TotalUsersLeft))) #and -gt than #formula to calc optimal batch size for the rest#
            {
            Write-Host "Processing a batch of $($currentUserBatch.Count) users: $($currentUserBatch.UPN)" -ForegroundColor Cyan
            #<main parallell processing>
            $ScriptBlock = {
                param($BatchUser, $cred, $ScriptWorkDir)
                Write-Host "Processing $($BatchUser.Upn) inside the batch job" -ForegroundColor grey
                Move-CsUser -Identity "sip:$($BatchUser.UPN)" -Target sipfed.online.lync.com -MoveToTeams -HostedMigrationOverrideUrl $(GetHostedMigrationServiceUrl) -Credential $cred -confirm:$false -BypassAudioConferencingCheck -BypassEnterpriseVoiceCheck -errorVariable MoveCsUserResultError -Report "$ScriptWorkDir\tmp\$($BatchUser.UPN).csv" -UseOAuth #| Out-Null
                }
            foreach($BatchUser in $currentUserBatch)
            {
                
            Start-Job -Name UserMoveJob $ScriptBlock -ArgumentList $BatchUser,$cred, $ScriptWorkDir | Out-Null
            $UserMoveJob = Get-Job -Name UserMoveJob
            }
            #</main parallell processing>

           #<Process batch results>
            #Wait for all jobs to complete
            While ($UserMoveJob.State -eq "Running") { Start-Sleep 1 }
            #Get batch job output
            $JobOutput = Receive-Job $UserMoveJob #-Keep
            $UserMoveJob | Remove-Job
            
            foreach($BatchUser in $currentUserBatch)
            {
            $UserMoveReport = import-csv "$ScriptWorkDir\tmp\$($BatchUser.UPN).csv"
            "$($UserMoveReport.StartTime),MoveToTeams,$($BatchUser.UPN),$($UserMoveReport.ErrorMsg)" | Out-File $MoveResultsLog -Append
            #If user move failed, add it to an array
            if ($UserMoveReport.ErrorMsg -ne "Success") {
            $global:RetryUsers += New-Object -TypeName psobject -Property @{
                UPN = $BatchUser.UPN
                ErrorMsg = $UserMoveReport.ErrorMsg}
            }
            }

            #</Process batch results>

            #Clear the batch variables
            $BatchUserCounter = 0
            $currentUserBatch = @()
            }
    }
    #Report move summary
    
    $EndTime = Get-Date
    $SuccessfullyMigrated = $UsersWithPrereqsMet.Count - $global:RetryUsers.Count
    $EncountedErrors = $($global:RetryUsers | Group-Object -Property ErrorMsg -NoElement | ft)
    Write-Host ""
    Write-Host "===================================================="
    Write-Host "                    Move SUMMARY                    " -BackgroundColor DarkMagenta
    Write-Host "Moved Successfully:`t$($MoveUserList.Count - $global:RetryUsers.Count)" #-ForegroundColor Green
    Write-Host "Failed to move: `t$($global:RetryUsers.Count)" -ForegroundColor Red
    Write-Host "Time taken: `t`t$($EndTime-$StartTime)" #-BackgroundColor Magenta
    Write-Host "===================================================="
    Write-Host ""
    Write-Host "Encounted errors:" -ForegroundColor Red
    $global:RetryUsers | Group-Object -Property ErrorMsg -NoElement | ft -AutoSize
    Write-host "Log file:`t`t`t $MoveResultsLog"
    Write-Host "                                                    " -BackgroundColor DarkMagenta
    Write-Host "===================================================="
    Write-Host ""

    "$EndTime,MoveSummary,Moved Successfully: $($MoveUserList.Count - $global:RetryUsers.Count),Failed to move: $($global:RetryUsers.Count),Time taken: $($EndTime-$StartTime)" | Out-File $MoveResultsLog -Append

}



if ($SkipAllPrerequisiteChecks)
{
    #Process ALL users from input csv
    BatchMoveUsers $inputuserslist 
}
else
{
    #Check pre-reqs and store users that met them in $UsersWithPrereqsMet
    CheckPrerequisites $InputUsersList
    #Process users that met the pre-reqs ($UsersWithPrereqsMet)
    BatchMoveUsers $UsersWithPrereqsMet
}

#Retry users that failed to move ($RetryCycles x times)
for ($i = 1; $i -le $RetryCycles; $i++) 
{
#Start-Sleep 2400
Write-Host "########### Retrying users that failed to move (Total: $($global:RetryUsers.Count)). Retry Attempt#: $i)" -ForegroundColor Yellow -BackgroundColor Blue
BatchMoveUsers $global:RetryUsers
}
