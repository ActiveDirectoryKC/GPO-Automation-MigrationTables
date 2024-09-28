<#
.SYNOPSIS
Generates a new migration table from a template migration table, a backed up gpo, and the name of a new GPO.

.DESCRIPTION
Generates a new migration table from a template migration table, a backed up gpo, and the name of a new GPO.
New migration table items generated from a configuration file that can be generated from a first run.

.PARAMETER TargetGroupPolicyName
Specify the name of the new group policy where settings will be imported into. Defaults to 'User Rights - Servers Policy'.

.PARAMETER BackupGroupPolicyPath
Specify the path of the backed up group policy where settings will be imported from.

.PARAMETER NewMigrationTablePath
Specify the path of the new migration table file. Defaults to the backup GPO Backup directory and name.

.PARAMETER ConfigurationFilePath
Specify the path of configuration file to use. See script help for details on defaults.

.PARAMETER ValidateMigrationTable
Specify to validate the new migration table against a test GPO.

.EXAMPLE
.\New-ADKCMigrationTableFromTemplate.ps1 -TargetGroupPolicyName "Test Policy 2024" -BackupGroupPolicyName zTEMPLATE-SERVERS-USER-RIGHTS -BackupGroupPolicyPath .\ -CreateMigrationTableTemplate -Verbose
.\New-ADKCMigrationTableFromTemplate.ps1 -TargetGroupPolicyName "Test Policy 2024" -BackupGroupPolicyName zTEMPLATE-SERVERS-USER-RIGHTS -BackupGroupPolicyPath .\ -CreateMigrationTableTemplate -UseTheDefaultGroupNames -OverrideGroupDomainChecking -TargetServerRole TEST -Verbose 

.NOTES
.VERSION 0.6.0
.CREATED BY Tyler Jacobs (ActiveDirectoryKC.NET / poolmanjim)
.TODO
    
    0.7.0   - Support removing blank entries in migration table?
            - Change $ConfigurationFileTemplate to include the default values comprehensively and just trim them out if we're not adding the values?
            - Test Validation option
            - Add default group name?
            - Add more documentation (funcitons, notes, etc.). Script has gotten complicated. 
    0.8.0   - Support more with the backups
            - Support creating template migration table from file not just raw GPO path.
            - Support using an existing GPO and not a backup file.
            - Support backing up the gpo to file if it hasn't been already
            - Support zipping/unziping backups to create tables.

.CHANGELOG
    0.6.0   
    - Fill in New Migraiton Table with default groups, if they are detected.
    - Typos clean up.
    - Fixed wait loop to be a function and to allow for going from new config straight to new migration table.

.LICENSE MIT License
    MIT License

    Copyright (c) 2024 ActiveDirectoryKC.NET

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

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false,HelpMessage="Specify the name of the new group policy where settings will be imported into. Defaults to 'User Rights - Servers Policy'.")]
    [ValidateNotNull()]
    [string]$TargetGroupPolicyName = "User Rights - Servers Policy",

    [Parameter(Mandatory=$false,HelpMessage="Specify the name of the backed up gpo. Defaults to 'zTEMPLATE-SERVERS-USER-RIGHTS'.")]
    [string]$BackupGroupPolicyName = "zTEMPLATE-SERVERS-USER-RIGHTS",

    [Parameter(Mandatory=$true,HelpMessage="Specify the path of the backed up group policy where settings will be imported from.")]
    [ValidateScript({
        if( !(Test-Path -Path $_) )
        {
            throw [System.IO.DirectoryNotFoundException]::new("Unable to locate the backup files specified by '$_' - Exiting")
        }
        elseif( (Get-Item -Path $_) -is [System.IO.FileInfo] )
        {
            throw [System.IO.InvalidDataException]::new("Unable to locate the backup directory. The path '$_' resolves to a file and not a directory - Exiting")
        }
        else
        {
            return $true
        }
    })]
    [string]$BackupGroupPolicyPath,

    [Parameter(Mandatory=$false,HelpMessage="Specify to create the migration table template from a backup if it doesn't already exist.")]
    [switch]$CreateMigrationTableTemplate,

    [Parameter(Mandatory=$false,HelpMessage="Specify the path of the new migration table file. Defaults same directory as the configuration (current directory).")]
    [string]$NewMigrationTablePath,

    [Parameter(Mandatory=$false,HelpMessage="Specify the path of configuration file to use. See script help for details on defaults.")]
    [string]$ConfigurationFilePath,

    [Parameter(Mandatory=$false,HelpMessage="Specify to validate the new migration table against a test GPO.")]
    [switch]$ValidateMigrationTable,

    [Parameter(Mandatory=$false,HelpMessage="Specify to use the default groups in the new migration table.")]
    [switch]$UseTheDefaultGroupNames,

    [Parameter(Mandatory=$false,HelpMessage="Specify to override domain checking for groups.")]
    [switch]$OverrideGroupDomainChecking,

    [Parameter(Mandatory=$false,HelpMessage="Specify the name of the target server role the new migration table and policies is intended to target.")]
    [string]$TargetServerRole = "TEST"
)

$Configuration = @{}
$ConfigurationFileTemplate = @{
    "V_LOCAL_ADMIN_GROUP" = ""
    "V_LOGON_BATCH_GROUP" = ""
    "V_LOGON_LOCAL_GROUP" = ""
    "V_LOGON_NETWORK_GROUP" = ""
    "V_LOGON_RDP_GROUP" = ""
    "V_LOGON_SERVICE_GROUP" = ""
    "V_DENY_BATCH_GROUP" = ""
    "V_DENY_LOGON_BATCH_GROUP" = ""
    "V_DENY_LOGON_LOCAL_GROUP" = ""
    "V_DENY_LOGON_NETWORK_GROUP" = ""
    "V_DENY_LOGON_RDP_GROUP" = ""
    "V_DENY_LOGON_SERVICE_GROUP" = ""
    "V_DOMAIN_ADMINS_GROUP" = ""
    "V_ENTERPRISE_ADMINS_GROUP" = ""
    "V_SERVICE_ACCOUNTS_GROUP" = ""
    "V_DENY_INTERACTIVE_LOGON_GROUP" = ""
}

$DefaultProductionGroupsMapping = @{
    "X_LOCAL_ADMIN_GROUP" = "dlLocalAdmins{ServerRole}"
    "X_LOGON_BATCH_GROUP" = "dlURALogonBatch{ServerRole}"
    "X_LOGON_LOCAL_GROUP" = "dlURALogonLocal{ServerRole}"
    "X_LOGON_NETWORK_GROUP" = "dlURALogonNetwork{ServerRole}"
    "X_LOGON_RDP_GROUP" = "dlURALogonRDP{ServerRole}"
    "X_LOGON_SERVICE_GROUP" = "dlURALogonService{ServerRole}"
    "X_DENY_LOGON_BATCH_GROUP" = "dlURADENYLogonBatch{ServerRole}"
    "X_DENY_LOGON_LOCAL_GROUP" = "dlURADENYLogonLocal{ServerRole}"
    "X_DENY_LOGON_NETWORK_GROUP" = "dlURADENYLogonNetwork{ServerRole}"
    "X_DENY_LOGON_RDP_GROUP" = "dlURADENYLogonRDP{ServerRole}"
    "X_DENY_LOGON_SERVICE_GROUP" = "dlURADENYLogonService{ServerRole}"
    "X_SERVICE_ACCOUNTS_GROUP" = "gruServiceAccounts"
    "X_DENY_INTERACTIVE_LOGON_GROUP" = "gruDENY_INTERACTIVE_LOGON"
    "X_DOMAIN_ADMINS_GROUP" = "Domain Admins" # Don't change this one
    "X_ENTERPRISE_ADMINS_GROUP" = "Enterprise Admins" # Don't change this one
}

[string]$ConfigurationDirectory = ""
$GroupPolicies = Get-GPO -All -Domain $DomainName -Server $DomainController
[string]$BackupGPOParentPath = ""
[string]$TemplateMigrationTablePath = ""
[string]$NewMigrationTableDirectory = ""
[string]$NewMigrationTablePath = ""

$DomainObj = Get-ADDomain -Current LocalComputer
$DomainName = $DomainObj.DnsRoot
$DomainNBN = $DomainObj.NetbiosName
$DomainController = (Get-ADDomainController -Discover -DomainName $DomainName -AvoidSelf).hostname[0]

Write-Verbose "Script Path: $PSScriptRoot"

# https://stackoverflow.com/questions/3740128/pscustomobject-to-hashtable
function ConvertFromPSObjectToHashTable
{
    param(
        [Parameter(ValueFromPipeline=$true)]
        [ValidateNotNull()]
        [object]$InputObject
    )

    if( $InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string] )
    {
        $OutputCollection = [System.Collections.Generic.List[object]]::new() # Lazy Collection.
        foreach( $Object in $InputObject )
        {
            $OutputCollection.Add( (ConvertFromPSObjectToHashTable -InputObject $object) )
        }

        Write-Output -NoEnumerate $OutputCollection
    }
    elseif( $InputObject -is [psobject] )
    {
        $ObjectHashTable = @{}

        foreach( $ObjProperty in $InputObject.psobject.Properties )
        {
            $ObjectHashTable[$ObjProperty.Name] = (ConvertFromPSObjectToHashTable -InputObject $ObjProperty.Value).PSObject.BaseObject
        }

        return $ObjectHashTable
    }
    else
    {
        return $InputObject
    }
}

<#
.SYNOPSIS
[private] Resolves the migration table template from a GPO backup and saves the template. 

.DESCRIPTION
[private] Resolves the migration table template from a GPO backup and saves the template. 

.PARAMETER TargetGPODisplayName
Specify the name of the GPO to pull migration table entries from.

.PARAMETER MigrationTableOutputPath
Specify the file path to export the migration table.

.EXAMPLE
NewGPOMigrationTableFromBackup -TargetGPODisplayName "Test GPO" -MigrationTableOutputPath C:\temp\TestGPOMigrationTable.migtable

.NOTES
.TODO 
- Add ability to import from a backup file and not just from a targeted group policy.
#>
function NewGPOMigrationTableFromBackup
{
    param(
        [Parameter(Mandatory=$true,HelpMessage="Specify the name of the GPO to pull migration table entries from.")]
        [string]$TargetGPODisplayName,

        [Parameter(Mandatory=$true,HelpMessage="Specify the file path to export the migration table.")]
        [string]$MigrationTableOutputPath
    )

    Process
    {
        # Using non AD PowerShell for speed and reduce dependency on PowerShell module if this ever split out.
        if( !$script:DomainName )
        {
            $script:DomainName = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain().Name
            # 0 indicates domain - https://learn.microsoft.com/en-us/dotnet/api/system.directoryservices.activedirectory.directorycontexttype?view=net-8.0
            $DomainContext = [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new(0,$script:DomainName)
            $script:DomainController = ([System.DirectoryServices.ActiveDirectory.DomainController]::FindOne($DomainContext)).Name # DC Locator requires a "connection" to a domain.
        }

        if( !$MigrationTableOutputPath )
        {
            Write-Verbose -Message "No MigrationTableOutputPath specified - Discovering one based on script path"
            if( $PSScriptRoot )
            {
                $MigrationTableOutputPath = $PSScriptRoot # Script Directory
            }
            else
            {
                $MigrationTableOutputPath = Get-Location # Current directory
            }
            Write-Host -Object "SUCCESSFULLY set migration table template output path to '$MigrationTableOutputPath'"
        }
        else
        {
            Write-Host -Object "Migration table template output will output to the following directory '$MigrationTableOutputPath'"
        }

        ## TODO: Can this be condensed into one check?
        if( [System.IO.Path]::GetExtension($MigrationTableOutputPath) -ne ".migtable" )
        {
            $MigrationTableOutputFullPath = "$MigrationTableOutputPath\$TargetGPODisplayName.migtable"
        }
        else
        {
            $MigrationTableOutputFullPath = $MigrationTableOutputPath
        }

        if( !(Test-Path -Path $MigrationTableOutputFullPath) )
        {
            try
            {
                $null = New-Item -Path $MigrationTableOutputFullPath -ItemType File -ErrorAction Stop
                Write-Host -Object "SUCCESSFULLY created new migration table at path '$MigrationTableOutputFullPath'"
            }
            catch
            {
                Write-Error -Message "Failed to create migration table file at '$MigrationTableOutputFullPath' - $($PSItem.Exception.Message)"
                throw $PSItem
            }
        }

        #region Connect to GPMGMT and Setup Object
        try
        {
            $GpmObj = New-Object -ComObject "GPMGMT.GPM" -ErrorAction Stop
            $GpmConstants = $GpmObj.GetConstants()
            $GpmSearch = $GpmObj.CreateSearchCriteria()
            # 0 indicates to use the DC specified. UseAnyDC will just look randomly.
            Write-Verbose -Message "Migration Table - Target GPO: $TargetGPODisplayName"
            $GpmSearch.Add( $GpmConstants.SearchPropertyGPODisplayName, $GpmConstants.SearchOpEquals, $TargetGPODisplayName )
        }
        catch
        {
            Write-Error -Message "Unable to create an com object or gather data for GPMgmt. Cannot create new migration tables - $($PSItem.Exception.Message)"
            throw $PSItem
        }
        #endregion Connect to GPMGMT and Setup Object

        #region Connect to GPMGMT Domain
        try
        {
            $GpmDomain = $GpmObj.GetDomain( $script:DomainName, $script:DomainController, 0 )
            # 0 indicates to use the DC specified. UseAnyDC will just look randomly.

            if( !$GpmDomain ) { throw "UNKNWON - FAILED TO GET GPMDOMAIN" }
        }
        catch
        {
            Write-Error -Message "Unable to connect to the domain '$script:DomainName' using the GPMgmt tools - $($PSItem.Exception.Message)"
            throw $PSItem
        }
        #endregion Connect to GPMGMT Domain

        #region Find GPOs matching the criteria
        try
        {
            $FoundGPOs = $GpmDomain.SearchGpos($GpmSearch)
        }
        catch
        {
            Write-Error -Message "Failed to generate a list of policies from GPMmgmt in the domain '$script:DomainName' - $($PSItem.Exception.Message)"
            throw $PSItem
        }

        if( !($FoundGPOs) -or $FoundGPOs.Count -lt 1 )
        {
            throw "Failed to locate a policy in the domain '$script:DomainName' matching the name '$TargetGPODisplayName' - Exiting"
        }
        elseif( $FoundGPOs.Count -gt 1 )
        {
            throw "Search criteria returned too many policies m matching the name '$TargetGPODisplayName' in the domain '$script:DomainName' - Exiting"
        }
        #endregion Find GPOs matching the criteria

        #region Create Migration Table
        try
        {
            foreach( $FoundGPO in $FoundGPOs ) # Should ONLY ever be one. WE check that above.
            {
                Write-Verbose -Message "Migration Table - Found GPO Names: $($FoundGPO.DisplayName)"
                Write-Verbose -Message "Migration Table - Found GPO Count: $($FoundGPO.Count)"

                $NewMigrationTable = $GpmObj.CreateMigrationTable()
                $NewMigrationTable.Add( $GpmConstants.ProcessSecurity, $FoundGPO )
                foreach( $NewMigTableEntry in $NewMigrationTable.GetEntries() )
                {
                    if( $NewMigTableEntry.Source -like "X_*" )
                    {
                        $null = $NewMigrationTable.UpdateDestination( $NewMigtableEntry.Source, ($NewMigtableEntry.Source).replace("X_","V_") )
                    }
                    else
                    {
                        $null = $NewMigrationTable.DeleteEntry( $NewMigtableEntry.Source )
                    }
                }

                Write-Verbose -Message "Saving template migration table to '$MigrationTableOutputFullPath'"
                $null = $NewMigrationTable.Save( $MigrationTableOutputFullPath )
                Write-Host -Object "SUCCESSFULLY saved new migration table to '$MigrationTableOutputFullPath'"
                return $MigrationTableOutputFullPath
            }
            #endregion Create Migration Table
        }
        catch
        {
            Write-Error -Message "Failed to create a new migration table from '$($TargetGPO.DisplayName)' in the domain '$script:DomainName' - $($PSItem.Exception.Message)"
            throw $PSItem
        }
    }

    End
    {
        ## TODO: End
        $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject( $GpmObj )
    }
}

<#
.SYNOPSIS
[prviate function] Resolves account/group names to the domain and inserts them in the input hash table.

.DESCRIPTION
[prviate function] Resolves account/group names to the domain and inserts them in the input hash table.

.PARAMETER InputHashTable
Specifies the hashtable to modify with the new values.

.PARAMETER OverrideGroupDomainChecking
Specifies to skip attempting to resolve the group in AD and just do a string replacement.

.EXAMPLE
ResolveGPOMigrationDefaultDomainGroups -InputHashTable $Configuration -OverrideGroupDomainChecking
#>
function ResolveGPOMigrationDefaultDomainGroups
{
    param(
        [Parameter(Mandatory=$true,HelpMessage="Specifies the hashtable to modify with the new values.")]
        [hashtable]$InputHashTable, ## TODO: Better naming/typing.

        [Parameter(Mandatory=$true,HelpMessage="Specifies to skip attempting to resolve the group in AD and just do a string replacement.")]
        [switch]$OverrideGroupDomainChecking
    )

    Write-Verbose -Message "Input Hashtable"
    if( $VerbosePreference )
    {
        foreach( $Key in $InputHashTable.Keys )
        {
            Write-Verbose -Message "`t $($Key): $($InputHashTable.$Key)"
        }
    }
    Write-Verbose -Message "OverrideGroupDomainChecking: $OverrideGroupDomainChecking"

    foreach( $GroupMapping in $DefaultProductionGroupsMapping.Keys )
    {
        $MappedGroupName = $GroupMapping.replace("X_","V_")
        Write-Verbose -Message "Remapped '$GroupMapping' to '$MappedGroupname' if different"

        $MigrationTableGroupName = ($DefaultProductionGroupsMapping.$GroupMapping).replace("{ServerRole}",$script:TargetServerRole)

        if( $InputHashTable.ContainsKey($MappedGroupName) )
        {
            if( !$OverrideGroupDomainChecking ) ## TODO: FIgure out how to access parent PSBoundParamters from child.
            {
                $MigrationTableGroup = Get-ADGroup -Filter "Name -eq '$MigrationTableGroupName'" -Server $script:DomainController

                if( $MigrationTableGroup )
                {
                    $InputHashTable.$MappedGroupName = "$DomainNBN\$($MigrationTableGroup.Name)"
                    Write-Verbose -Message "Found group matching '$($MigrationTableGroup.Name) in $script:DomainName - '$DomainNBN\$($MigrationTableGroup.Name)'"
                }
                else
                {
                    Write-Warning -Message "Failed to find a group matching '$MigrationTableGroupName' in $script:DomainName - Skipping"
                }
            }
            else
            {
                $InputHashTable.$MappedGroupName = "$script:DomainNBN\$MigrationTableGroupName"
                Write-Verbose -Message "Adding unresolved group '$MigrationTableGroupName' in $script:DomainName to configuration."
            }
        }
        # else, do nothing.
    }
}

## TODO: Make more generic so we can reuse some more.
function WaitBeforeScriptClose
{
    param( [int]$WaitForSeconds = 15 )
    $WaitCounter = 0
    while( $WaitCounter -le $WaitForSeconds )
    {
        $remaining = $WaitForSeconds - $WaitCounter
        Write-Progress -Activity "Script will return in 30 seconds" -Status "$remaining seconds until script closes" -PercentComplete ($WaitCounter / $WaitForSeconds * 100)

        if( $WaitCounter -ge $WaitForSeconds ) { Write-Progress -Activity "Waiting until script exits" -Status "$remaining seconds until script closes" -PercentComplete 100 }
        $WaitCounter++
        Start-Sleep -Seconds 1
    }
}

#region Parameter Validation - BackupGroupPolicyPath
if( !(Test-Path -Path $BackupGroupPolicyPath) )
{
    # The validate script should capture this. This is a just-in-case.
    throw [System.IO.DirectoryNotFoundException]::new("Unable to locate the backup directory (or files) specified by '$BackupGroupPolicyPath' - Exiting")
}
elseif( (Get-Item -Path $BackupGroupPolicyPath) -is [System.IO.FileInfo] )
{
    # The validate script should capture this. This is a just-in-case.
    throw [System.IO.InvalidDataException]::new("Unable to locate the backup files. The path '$BackupGroupPolicyPath' resolves to a directory and not a file - Exiting")
}
else
{
    Write-Verbose -Message "Backup GPO Path: $BackupGroupPolicyPath"
    $BackupGPO_Temp = Get-Item -Path $BackupGroupPolicyPath
    $BackupGPOParentPath = Split-Path -Path $BackupGPO_Temp -Parent # Resolves the parent directory
}
#endregion Parameter Validation - BackupGroupPolicyPath

#region Migration Table Template/Default Processing
# Target the Template Migration Table.
$TemplateMigrationTablePath = "$PSScriptRoot\$BackupGroupPolicyName.migtable"
if( !(Test-Path -Path $TemplateMigrationTablePath) )
{
    Write-Verbose -Message "Cannot find migration table at '$TemplateMigrationTablePath'"

    if( $PSBoundParameters.ContainsKey("CreateMigrationTableTemplate") )
    {
        Write-Verbose -Message "Parameter specified 'CreateMigrationTableTemplate' - Creating migration table template"
        Write-Verbose -Message "BackupGroupPolicyName: $BackupGroupPolicyName"
        Write-Verbose -Message "TemplateMigrationTablePath: $TemplateMigrationTablePath"

        $TemplateMigrationTablePath = NewGPOMigrationTableFromBackup -TargetGPODisplayName $BackupGroupPolicyName -MigrationTableOutputPath $TemplateMigrationTablePath

        if( !$TemplateMigrationTablePath ) { throw "Failed to create new migration table - UNKNOWN ERROR"  }
    }
    else
    {
        throw [System.IO.FileNotFoundException]::new("Unable to locate the migration table file in the backup directory - '$TemplateMigrationTablePath' - Exiting")
    }
}
#endregion Migration Table Template/Default Processing


#region Import/Create Configuration File
# Create a new configuration file if one isn't found.
if( !$PSBoundParameters.ContainsKey("ConfigurationFilePath") )
{
    if( $PSScriptRoot )
    {
        $ConfigurationDirectory = $PSScriptRoot
        Write-Verbose -Message "Setting configuration directory to script root: $PSScriptRoot"
    }
    else
    {
        $ConfigurationDirectory = Get-Location
        Write-Verbose -Message "Setting configuration directory to current directory: $(Get-Location)"
    }
    $ConfigurationFilePath = "$ConfigurationDirectory\$TargetGroupPolicyName.json"
    Write-Warning -Message "No configuration path supplied - Using '$ConfigurationFilePath'"
}

if( !(Test-Path -Path $ConfigurationFilePath) )
{
    if( !$ConfigurationDirectory )
    {
        $ConfigurationDirectory = Split-Path -Path $ConfigurationFilePath -Parent
    }

    Write-Warning -Message "Unable to validate configuration file path '$ConfigurationFilePath' - Prompting to create configuration file"
    if( $PSCmdlet.ShouldContinue( $ConfigurationDirectory ,"Would you like to create the configuration file in the following directory?") -or (!$Confirm) -or $Force )
    {
        try
        {
            $ConfigFile = New-Item -Path $ConfigurationDirectory -Name "$TargetGroupPolicyName.json" -ItemType File -ErrorAction Stop
            Write-Host "SUCCESSFULLY created configuration file at $ConfigurationDirectory with the name '$TargetGroupPolicyName.json'" -ForegroundColor Cyan
        }
        catch
        {
            Write-Error -Message "Failed to create configuration file at '$ConfigurationDirectory' - $($PSItem.Exception.Message)"
            throw $PSItem
        }

        if( $ConfigFile )
        {
            if( $PSBoundParameters.ContainsKey("UseTheDefaultGroupNames") )
            {
                ResolveGPOMigrationDefaultDomainGroups -InputHashTable $ConfigurationFileTemplate -OverrideGroupDomainChecking:$OverrideGroupDomainChecking
            }

            try
            {
                $null = $ConfigurationFileTemplate | ConvertTo-Json -Depth 2 -ErrorAction Stop | Out-File $ConfigFile.FullName -ErrorAction Stop
                Write-Host "SUCCESSFULLY exported configuration settings to the configuration file" -ForegroundColor Cyan
            }
            catch
            {
                Write-Error -Message "Failed to export configuration settings to the configuration file at '$($ConfigFile.FullName)' - $($PSItem.Exception.Message)"
                throw $PSItem
            }

        }
    }

    if( !$PSBoundParameters.ContainsKey("UseTheDefaultGroupNames") )
    {
        Write-Warning -Message "Script cannot continue until you modify the configuration file with your desired settings - Exiting"

    }
    else
    {
        $Configuration = $ConfigurationFileTemplate
        Write-Host -Object "SUCCESSFULLY created configuration from default"
    }

    if( !$PSBoundParameters.ContainsKey("UseTheDefaultGroupNames") )
    {
        WaitBeforeScriptClose
        return $null
    }
}
elseif( Test-Path -Path $ConfigurationFilePath )
{
    if( !$ConfigurationDirectory )
    {
        $ConfigurationDirectory = Split-Path -Path $ConfigurationFilePath -Parent
    }
    try
    {
        if( $PSVersionTable.PSVersion.Major -lt 6 )
        {
            $Configuration = Get-Content -Path $ConfigurationFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | ConvertFromPSObjectToHashTable
        }
        else # Use the more streamlined version if we can.
        {
            $Configuration = Get-Content -Path $ConfigurationFilePath -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }

        Write-Host -Object "SUCCESSFULLY imported the configuration from '$ConfigurationFilePath'"
    }
    catch
    {
        Write-Error -Message "Failed to import configuration file at '$ConfigurationFilePath' - $($PSItem.Exception.Message)"
        throw $PSItem
    }

    foreach( $ConfigItemKey in $Configuration.Keys )
    {
        $ExitCondition = $false # Used to know if the config is screwed up and we need to back out after checking the values.
        if( $Configuration.$ConfigItemKey -isnot [string] )
        {
            Write-Error -Message "Script does not support other object types other than string for values in the migration table - KEY: $ConfigItemKey, VALUE TYPE: $($Configuration.$ConfigItemKey.Gettype().Name)  - This will cause the script to exit..."
            $ExitCondition = $true
        }
    }

    if( $ExitCondition )
    {
        return "ERR_BAD_CONFIG"
    }
}
#endregion Import/Create Configuration File

#region Create the New Migration Table
if( !$PSBoundParameters.ContainsKey("NewMigrationTablePath") )
{
    $NewMigrationTablePath = "$ConfigurationDirectory\$TargetGroupPolicyName.migtable"
    Write-Verbose -Message "No NewMigrationTablePath specified setting it to '$NewMigrationTablePath'"
}
else
{
    if( (Get-Item -Path $NewMigrationTablePath) -is [System.IO.DirectoryInfo] )
    {
        $NewMigrationTablePath = "$NewMigrationTablePath\$TargetGroupPolicyName.migtable"
        Write-Verbose -Message "NewMigrationTablePath is a directory - Adding a filename to the path"
    }
}

if( Test-Path -Path $TemplateMigrationTablePath )
{
    try
    {
        $NewMigrationTable = Get-Content -Path $TemplateMigrationTablePath -ErrorAction Stop
        Write-Verbose -Message "Successfully read the migration table file '$TemplateMigrationTablePath'"
    }
    catch
    {
        Write-Host -Object "Failed to read the contents of the migration table file - $($PSItem.Exception.Message)"
        throw $PSItem
    }

    foreach( $MigrationTableEntry in $Configuration.Keys )
    {
        ## TODO: Prompt to add an entry from default?
        ## TODO: Remove entries that are blank.
        if( !$Configuration.$MigrationTableEntry )
        {
            Write-Warning -Message "No mapping exists for entry '$MigrationTableEntry' - Skipping"
        }
        else
        {
            $NewMigrationTable = $NewMigrationTable.replace($MigrationTableEntry, $Configuration.$MigrationTableEntry)
            Write-Verbose -Message "Altered the entry '$MigrationTableEntry' to '$($Configuration.$MigrationTableEntry)'"
        }
    }
    Write-Host -Object "COMPLETED modifying the entries for the migration table" -ForegroundColor Cyan

    try
    {
        $NewMigrationTableDirectory = Split-Path -Path $NewMigrationTablePath -Parent
        $NewMigrationTable | Out-File -FilePath $NewMigrationTablePath -NoClobber -ErrorAction Stop
        Write-Host -Object "SUCCESSFULLY exported the new migration table to '$NewMigrationTablePath'"
    }
    catch
    {
        Write-Host -Object "Failed to export the new migration table to file - $($PSItem.Exception.Message)"
        throw $PSItem
    }
    $NewMigrationTable = $null # Just cleaning up

    Write-Host -Object "##############################"
    Write-Host -Object ""
    Write-Host -Object "Exported the new migration table to the following path: " -NoNewline
    Write-Host -Object "$NewMigrationTablePath" -ForegroundColor Cyan
    Write-Host -Object ""
    Write-Host -Object "##############################"
}

#endregion Create the New Migration Table

#region Validate Migration Table
if( $PSBoundParameters.ContainsKey("ValidateMigrationTable") )
{
    $TestGPOName = "TEST MIGRATION TABLE $(Get-Date -Format yyyyMMddHHmmss)"

    if( ($GroupPolicies) -contains $TestGPOName )
    {
        # If somehow we have a duplicate name, use the name we came up with and throw a random partial GUID at the end.
        # If that is somehow not unique enough, we've got bigger problems.
        $TestGPOName += " $( ([System.Guid]::NewGuid().ToString()).split("-")[-1] )"

        if( ($GroupPolicies) -contains $TestGPOName )
        {
            throw "Cannot create test group policy - Too many test policy names"
        }
    }
    else
    {
        if( $PSCmdlet.ShouldContinue($TestGPOName,"Do you want to create the test gpo with the following name?") -or (!$Confirm) -or $Force )
        {
            # Create the Test GPO
            try
            {
                $TestGPO = New-GPO -Name $TestGPOName -Comment "TEST MIGRATION POLICY GPO `nCreated On: $(Get-Date) `nCreated By: $ENV:USERDOMAIN\$ENV:USERNAME" -Server $DomainController -Domain $DomainName -ErrorAction Stop
                $TestGPO.GpoStatus = "AllSettingsDisabled" # Disable settings so this can't be accidentially linked.
                Write-Host -Object "SUCCESSFULLY created the test GPO '$TestGPOName'" -ForegroundColor Cyan
            }
            catch
            {
                Write-Error -Message "Failed to create test GPO with name '$TestGPOName' - $($PSItem.Exception.Message)"
                throw $PSItem
            }

            try
            {
                $null = Import-GPO -BackupGpoName $BackupGroupPolicyName -TargetName $TestGPOName -Path $BackupGPOParentPath -MigrationTable "$NewMigrationTableDirectory\$TargetGroupPolicyName.migtable" -Server $DomainController -Domain $DomainName -ErrorAction Stop
                Write-Host -Object "SUCCESSFULLY imported the migration table onto '$TestGPOName'" -ForegroundColor Cyan
                Write-Host -Object "### NOTE ###" -ForegroundColor Yellow
                Write-Host -Object "Please review the settings and delete the policy when you are done confirming." -ForegroundColor Yellow
            }
            catch
            {
                Write-Error -Message "Failed to import settings onto the test GPO with name '$TestGPOName' using the new migration table - $($PSItem.Exception.Message)"
                throw $PSItem
            }

            try
            {
                $null = Get-GPOReport -Name $TestGPOName -Path ".\$TestGPOname.htm" -ReportType HTML
                Write-Host -Object "SUCCESSFULLY generated a report for the test gpo '$TestGPOName'" -ForegroundColor Cyan

                if( $PSCmdlet.ShouldContinue(".\$TestGPOName.htm","Do you want to open the test policy gpo report in your browser?") )
                {
                    Start-Process -FilePath ".\$TestGpoName.htm"
                }
            }
            catch
            {
                Write-Warning -Message "Failed to create a gpo report for the test gpo '$TestGPOName' - $($PSItem.Exception.Message)"
            }
        }
    }
}
#endregion Validate Migration Table

WaitBeforeScriptClose -WaitForSeconds 15

<# TODO: GENERATE MIGRATION TABLE TEMPLATE
# https://c-nergy.be/blog/?p=3067

$Domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name

$TemplateMigTablePath = "C:\temp\TEMPLATE_MIGTABLE.migtable"

$GpmObj = New-Object -ComObject "GPMGMT.GPM"
$GpmConstants = $GpmObj.GetConstants()

# $Domain, $DomainController, $Constant
# https://learn.microsoft.com/en-us/windows/win32/api/gpmgmt/nf-gpmgmt-igpm-getdomain
$GpmDomain = $GpmObj.GetDomain($Domain,$null,$GpmConstants.UseAnyDC)
$GpmSearch = $GpmObj.CreateSearchCriteria()
## TODO: Narrow this down...
$TargetGPO = $GpoList | Where-Object { $_.DisplayName -eq 'zTEMPLATES-SERVERS-USER-RIGHTS' }
$GpoList = $GpmDomain.SearchGpos($GpmSearch)

$NewMigrationTable = $GpmObj.CreateMigrationTable()
$NewMigrationTable.Add( $GpmConstants.ProcessSecurity, $TargetGPO )

foreach( $NewMigtableEntry in $NewMigrationTable.GetEntries() )
{
    if( $NewMigtableEntry.Source -like "X_*" )
    {
        $NewMigrationTable.UpdateDestination( $NewMigtableEntry.Source, ($NewMigtableEntry.Source).replace("X_","V_") )
    }
    else
    {
        $NewMigrationTable.DeleteEntry( $NewMigtableEntry.Source )
    }
}

$NewMigrationTable.Save( $TemplateMigTablePath )
#>