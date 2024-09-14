<#
.DESCRIPTION
    This is a POC for a process showing how to use PowerShell, Group Policy, AD Group Policy Cmdlets, and Migration Tables to automate as much of what can be with Group Policy.
    THIS IS NOT A COMPLETE SCRIPT! THIS IS A PROOF OF CONCEPT (AKA TEST, AKA IT DOESN'T WORK)!

    Use this at your own risk. This is intended to be a guide to help understand how to do this, not always do it for every circumstance. 

    The author(s) of this script cannot be held liable for any impact caused to your environment by use of this script. You use it AS-IS with NO WARRANTY, implied or otherwise. 
    Don't be stupid.

.NOTES
.VERSION 1.0
.CREATED BY poolmanjim (AKA ActiveDirectoryKC.NET)
.LICENSE MIT License
    MIT License

    Copyright (c) 2024 ActiveDirectoryKC

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

.LINK
    https://github.com/ActiveDirectoryKC/GPO-Automation-MigrationTables
#>

# Standard Variables
$DomainObj = Get-ADDomain
$DomainName = $DomainObj.DnsRoot
$DomainNBN = $DomainObj.NetbiosName
$DomainController = (Get-ADDomainController -Discover -DomainName $DomainName -AvoidSelf).hostname[0]

# THESE ITEMS ARE TO MAKE THE SAMPLE MAKE SENSE/WORK
$ServerRoleName = "TEST"
$GPOBackupName = "zTEMPLATE-SERVERS-USER-RIGHTS"
$GPONewName = "User Rights - TEST Servers Policy"
$GPOBackupPath = "C:\temp\GPOBackups"
$MigTableTemplateName = "zTEMPLATE-SERVERS-USER-RIGHTS.migtable"
$MigrationTableName = "MIGTABLE-SERVERS-USER-RIGHTS.migtable"

# This is a hash table to store the key-value pairs for the in-migration table variable to actual group.
# You could add your own, just make sure you create the corresponding group before trying to do this or it may get a little odd.
$MigrationTableMap = @{
    "V_LOCAL_ADMIN_GROUP" = "dlLocalAdmins$ServerRoleName`Servers"
    "V_LOGON_RDP_GROUP" = "dlURALogonRDP$ServerRoleName`Servers"
    "V_LOGON_LOCAL_GROUP" = "dlURALogonLocal$ServerRoleName`Servers"
    # You could add more...
}

#region Create User and Server Groups
# Location for the Groups we create.
$GroupsOU = Get-ADOrganizationalUnit -Filter "Name -eq 'Security Groups'"
if( !$GroupsOU )
{
    $GroupsOU = New-ADOrganizationalUnit -Name "Security Groups" -Path $DomainDN -PassThru
}

# A Test Group for the POC
$UserRoleTestGroup = Get-ADGroup -Filter "Name -eq 'gruTestUsers'"
if( !$UserRoleTestGroup )
{
    $UserRoleTestGroup = New-ADGroup -Name "gruTestUsers" -GroupCategory Security -GroupScope Global -Server $DomainController -PassThru -ErrorAction Stop
}

# Create a global group for the servers themselves to live in (for security filtering).
$ServerGlobalGroup = Get-ADGroup -Filter "Name -eq 'grc$ServerRoleName'"
if( !$ServerGlobalGroup )
{
    $ServerGlobalGroup = New-ADGroup -Name "grc$ServerRoleName" -GroupCategory Security -GroupScope DomainLocal -Path $GroupsOU -Server $DomainController -ErrorAction Stop -PassThru
}

#region Migration Table Replacement Groups
<# Just a reference block of code without the loops so you can see the "dumb" version of it.
    # Create group that we're going to delegate into the group as a local administrator. 
    $ServerLocalAdminsGroup = New-ADGroup -Filter "Name -eq 'dlLocalAdmins$ServerRoleName'"
    if( !$ServerLocalAdminsGroup )
    {
        $ServerLocalAdminsGroup = New-ADGroup -Name "dlLocalAdmins$ServerRoleName" -GroupCategory Security -GroupScope DomainLocal -Path $GroupsOU -Server $DomainController -ErrorAction Stop -PassThru
    }
#>

# Loop through the values on the migration table (the destination groups) and ensure the groups are created.
foreach( $DestinationGroupName in $MigrationTableMap.Values )
{
    $DestinationGroup = Get-ADGroup -Filter "Name -eq '$DestinationGroupName'" -Server $DomainController

    if( !($DestinationGroup) )
    {
        try
        {
            $DestinationGroup = New-ADGroup -Name $DestinationGroupName -GroupCategory Security -GroupScope DomainLocal -Path $GroupsOU -ErrorAction Stop -PassThru
            Write-Host -Object "SUCCESS - Created migration table destination group '$DestinationGroupName'"
        }
        catch
        {
            Write-Error -Object "Failed to create migration table destination group '$DestinationGroupName' - $($PSItem.Exception.Message)"
            if( $VerbosePreference ) { Write-Error -ErrorRecord $PSItem }
        }
    }
}

<# #### NOTE ####
    You'd still need to add members to those above groups.
    Add-ADGroupMember -Identity ($ServerLocalAdminsGroup.DistinguishedName) -Members $UserRoleTestGroup -Server $DomainController -ErrorAction Stop
#>
#endregion Migration Table Replacement Groups
#endregion Create User and Server Groups

#region Modify the Migration Table
# Alternatively you could put this on the sysvol: \\$DomainName\SYSVOL\$DomainName\MigrationTables\TEMPLATE-Servers-RestrictedGroups.migtable
$MigrationTableTemplate = Get-Content -Path "$GPOBackupPath\$MigTableTemplateName"
[string]$NewMigrationTable = ""

# Loop through the entries (sources) in the MigrationTableMap and replace the values accordingly in the migration table template.
foreach( $MigrationTableEntry in $MigrationTableMap.Keys )
{
    $NewMigrationTable = $MigrationTableTemplate.replace( $MigrationTableEntry, "$DomainNBN\$($MigrationTableMap.$MigrationTableEntry)" )
}
$NewMigrationTable | Out-File -FilePath "$GPOBackupPath\$MigrationTableName" -NoClobber ## TODO: Probably could be a better name here. 
#endregion Modify the Migration Table

#region Create Group Policy and Import Settings
<# #### OPTIONAL - This is assumed already done, but if you keep this in your AD as the master i may make sense to pull it down first. 
    $BackupGPO = Backup-GPO -Name "zTEMPLATE-User Rights - SERVER Restricted Groups" -Path $GPOBackupPath -Server $DomainController -PassThru
#>
$ServerGPO = New-GPO -Name $GPONewName -Server $DomainController -Comment "Created by Automation $(Get-Date -Format yyyyMMdd)"
$null = Import-GPO -BackupGpoName $GPOBackupName -TargetName $ServerGPO.DisplayName -Path $GPOBackupPath -MigrationTable "$GPOBackupPath\$MigrationTableName" -Server $DomainController
#endregion Create Group Policy and Import Settings

#region Security and Permissions Filtering on the Policy
# Rip out Authenticated Users from having permissions. This is to fix an issue later.
$NewPerms = $ServerGPO.GetSecurityInfo()
$AuthUsersTrustee = $NewPerms.Trustee.Where({ $PSItem.Name -eq 'Authenticated Users' })
$NewPerms.RemoveTrustee( $AuthUsersTrustee.Sid )
$ServerGPO.SetSecurityInfo( $NewPerms )

# Set the permissions to enable the server role group the ability to apply (Security Filtering) and Auth Users Read. 
Start-Sleep -Seconds 10 # Because this is a test and we're going faster than replication can occur. 
Set-GPPermission -Name $ServerGPO.DisplayName -PermissionLevel GpoApply -TargetName $ServerGlobalGroup.Name -TargetType Group
Set-GPPermission -Name $ServerGPO.DisplayName -PermissionLevel GpoRead -TargetName "Authenticated Users" -TargetType Group
#endregion Security and Permissions Filtering on the Policy