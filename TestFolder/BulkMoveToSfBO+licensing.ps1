#install-module msonline
Connect-MsolService

$TemplateUserUpn = "asmelovskiy@alexsm.msftonlinerepro.com"

#get disabled service plans from a template user
$myLicense = (Get-MsolUser -UserPrincipalName $TemplateUserUpn).Licenses.AccountSkuId.ToString()

#get disabled service plans from a template user
$myDisabledServicePlans = (Get-MsolUser -UserPrincipalName $TemplateUserUpn).LicenseAssignmentDetails.Assignments.DisabledServicePlans -join ","

$MyServicePlans = New-MsolLicenseOptions -AccountSkuId $myLicense -DisabledPlans "THREAT_INTELLIGENCE,EXCHANGE_ANALYTICS"

#Import users from CSV file
$MyUsers = Import-Csv -Path C:\Users\$env:USERNAME\Desktop\UsersToLicense.csv

#Assign licenses to users
foreach($user in $MyUsers){
    Set-MsolUserLicense -UserPrincipalName $user.UserPrincipalName -AddLicenses $DevAcctSku.AccountSkuId -LicenseOptions $MyServicePlans

}

#Set-MsolUserLicense -UserPrincipalName testuser1@alexsmonline.onmicrosoft.com -AddLicenses $myLicense -LicenseOptions $MyServicePlans

