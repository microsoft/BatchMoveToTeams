# Batch Move To Teams

This script is supposed to help large organizations to automate moving their Skype onprem users to Teams. Optimized to work up to 20 times faster on a large number of users in a batch (several thousands users and more) due to parallel processing. Eliminates most of manual work for Skype/Teams admin with auto retry logic for failed users and comprehensive reporting.

## Features
- **Move speed 10-20x faster due to parallel processing**    
  The script works 10-20 times faster than a traditional one as it executes user moves in parallel as much as possible (but not exceeding the cloud threshold of max user moves     at a time)
- **Automatic re-try logic for failed to move users**  
  For users who failed to move initially (e.g. throttling or some other error) the script will automatically retry them (3 times by default) so you don't have to do it manually
- **Move prerequisite checks**  
  Sort out and report users who don't meet the prerequisites so that the identified missing prerequisites can be corrected for those users.
- **Rich reporting capabilities**  
  Script provides comprehensive reporting for every action or check and will report each user processing and results at various stages of migration and also a summary of the       results, including how many were moved successfully, how many failed to migrate (grouped by the error message) how many were retried, etc. which is really helpful during the     migration to identify bottlenecks and address issues at an early stage

## Limitations

- The script will not work with o365 MFA enforced account
- The script currently does not support enabling PSTN calling capabilities in Teams (through Calling Plans or Direct Routing) for moved users. 

## Description

The script will process all users from the input CSV file (InputUsersCsv parameter). 

There are 2 main parts of the script:

1. **Check pre-requisites** before the move (Use SkipAllPrerequisiteChecks parameter to skip this step)  
   Below are the conditions that will ***trigger user to NOT be moved to Teams only*** (checks are performed in the order below. If a check fails, further cheks in the list won't be performed):
   - User does not exist onprem (onprem Get-CsUser fails)
   - If OuToSkip parameter is used, skip processing all users in the specified Active Directory Orgasnizational Unit 
   - User is already hosted in o365 (HostingProvider is sipfed.online.lync.com)
   - Either LineURI attribute is populated onprem or EnterpriseVoiceEnabled onprem attribute is set to True. You can override this by using ForceSkypeEvUsersToTeamsNoEV command line switch. 
   - User is not licensed for Skype and/or Teams in o365
2. **Move to Teams only**
   - Users will be moved in parallel batches (works 10-20 times faster than moving users one by one)
   - Users initially failed to move will be retried 3 times by default

## Parameters

#### InputUsersCsv
- Path to the csv file with users to be moved
#### ForceSkypeEvUsersToTeamsNoEV
- By default the script will not move Skype onprem users enabled for Enterprise Voice. If this parameter is used the script will forcefully move those users to Teams without EV functionality
#### SkipAllPrerequisiteChecks
- Will not perform any pre-requisite checks and try to move all users specified in the input file
#### OuToSkip
- Users located in this Organization Unit in local Active Directory will not be moved to Teams. Can be full OU DN or just a part of it. Wildcards are allowed.

## Inputs

A CSV file with user UPNs to be moved from Skype onprem to Teams only. "UPN" (without double quotes) must be the first line (header), than each user's UPN value on a separate line. E.g.:
```
UPN
testuser1@domain.com
testuser2@domain.com
testuser3@domain.com
```

## Outputs

**Log file to track the progress and results of the move.** The file will be created in the same directory as the input csv file (specified in inputUsersCsv parameter) and have a DateTime stamp appended to its name, e.g.: `c:\scripts\teamsmove\MoveResults_02-09-2021_17-15-01.txt`  

**Log file structure**. Use Excel to easily analyze:
- Individual user entries:
```
    Date/Time, Operation, UPN, Result, Result Details
      e.g.:
        02/16/2021 22:26:23,PrerequisiteCheck,Testmove3@contoso.com,ReadyToMove,User is ready to be moved to Teams
        02/16/2021 22:26:24,PrerequisiteCheck,Testmove4@contoso.com,Skipped,User not found
```
- Summary entries:
```
    Date/Time, Summary Operation, Succeeded #, Failed #, Time Taken
      e.g.:
        02/16/2021 22:26:25,PrereqSummary,Ready to move: 4,Pre-reqs not met: 3,Time taken: 00:00:04.3187720
        02/16/2021 22:26:34,MoveSummary,Moved Successfully: 4,Failed to move: 0,Time taken: 00:00:09.3513578
```

## Example

```ps
BatchMoveToTeams.ps1 -inputUsersCsv "C:\scripts\teamsmove\userlist.csv" -SkipAllPrerequisiteChecks -ForceSkypeEvUsersToTeamsNoEV -OuToSkip "OU=DisabledUsers,DC=contoso,DC=com" 
```

The above command will:
- Move users specified in the input csv file (_inputUsersCsv_ parameter)
- Bypass any prerequisite check SkipAllPrerequisiteChecks (_SkipAllPrerequisiteChecks_ parameter)
- Will not skip users enabled for Enterprise Voice in Skype onprem (By default Skype EV users are skipped, unless _ForceSkypeEvUsersToTeamsNoEV_ parameter is specified)
- Skip users in "OU=DisabledUsers,DC=contoso,DC=com" Organizational Unit in local Active directory (_OuToSkip_ parameter)

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.


