>[!NOTE]  
>THIS IS A DEV BRANCH!
>
>This is the 1.0.0 branch for the completed process. Currently this is still in development and not a fully working solution.
>A blog post with notes and details is pending. 
>
 
# GPO-Automation-MigrationTables
This is a process for creating new Group Policies from a administrator designed template policy. This will use PowerShell and migration tables to swap User Rights Assignments and Restricted groups on a template group policy and import those values into a new policy that reflects the resolved entries. This is a limited automation and only handles one part of the automation pipeline.

>[!WARNING]  
>THIS IS NOT A COMPLETE SCRIPT! THIS IS A PROOF OF CONCEPT (AKA TEST, AKA IT DOESN'T WORK)!
>
>Use this at your own risk. This is intended to be a guide to help understand how to do this, not always do it for every circumstance. The author(s) of this script cannot be held liable for any impact caused to your environment by use of this script. You use it AS-IS with >NO WARRANTY, implied or otherwise.
>
>Don't be stupid.


## CONTEXT
Automation with Group Policy is virtually impossible. The idea here is to automate a huge porition of the day-to-day type GPO work. I may write up some more detail as a blog post at some point on this, how it works, and why I made some of the choices I made. Nonetheless, I have used variations of this in large environments several times. 

## KNOWN ISSUES
1. NOT A WORKING SCRIPT - This is defintiely a POC script so it is very limited in functionality. I'm not intending to blow this up into an "automate your environment" script, at least not here. This is to cover this specific POC-type work.
2. DELAYS/UNOPTIMIZED - The script has some intentional delays built in because of replication slowness. If this were intended to be a production-ready script, that would worked out.
3. RBAC - There isn't a good way to RBAC this process due to the fact that several of the GPO commands lack the traditional AD switches (like -Credential). PowerShell JEA can be used but some of the ways it should work break so be warned.

<!-- 
RAW NOTES - NOT MEANT FOR PRIME-TIME, yet. 
User Rights Assignments
1. Create GPO named zTEMPLATE-SERVERS-USER-RIGHTS
2. Modify basic template settings
	Under Details Tab \ Click drop down for "GPO Status" and choose "User Configuration Settings Disabled". 
	Click OK
3. Edit the GPO
4. Expand Computer Configuration \ Policies \ Windows Settings \ Security Settings \ Local Policies.
5. D-Click on "User Rights Assignments"
6. For each setting you wish to configure via Group Policy double click the setting.
7. in the "Define these policy settings" dialog click on "Add User or Group".
8. Add the default system users (for example, Administrators should almost be added to everything). 
	Check MS baselines or check the Explain tab for details here.
9. Click "Add User or Group". In the text field enter X_[RIGHT]_GROUP.
10. Click OK.
11. Repeat the above steps for each permission needing delegated. 
12. Close out of Group Policy Mangement Console

Restricted Groups
1. Create GPO named zTEMPLATE-SERVERS-USER-RIGHTS
2. Modify basic template settings
	Under Details Tab \ Click drop down for "GPO Status" and choose "User Configuration Settings Disabled". 
	Click OK
3. Edit the GPO
4. Expand Computer Configuration \ Policies \ Windows Settings \ Security Settings \ Local Policies.
5. D-Click "Restricted Groups".
6. Right-Click in the white space. Choose "Add Group".
7. In the text field enter X_[RIGHT]_GROUP.
8. Click OK.
9. In the "Configure Membership" pop up, click Add next to "This group is a member of". 
10. Enter the system-level group the group would be nested into.
	Administrators and Remote Desktop Users
11. Click OK.
12. Repeat the above steps for each permission needing delegated. 
13. Close out of Group Policy Mangement Console

NOTE: I highly recommend adding a "Template version" item to the comments of each GPO template done this way.

Create a Migration Table
1. Launch GPMC.
2. Expand "Group Policy Objects".
3. Right-Click "Group Policy Objects" \ Choose "Open Migration Table Editor".
4. Tools \ Populate from GPO 
5. Select the policy you created earlier (e.g., zTEMPLATE-SERVERS-USER-RIGHTS).
6. Click "OK".
7. Locate each item you added that has your variable prefix (mine is X_). 
8. For each one of your added items. Set the "Destination Name" field to be V_[ITEM_NAME].
	For example: X_LOCAL_ADMIN_GROUP would have a destination name of "V_LOCAL_ADMIN_GROUP".
9. Remove an superfluous entries (ones that aren't domain specific). 
10. Click File \ Save As. 
11. Name the migration table "zTEMPLATE-SERVERS-USER-RIGHTS.migtable".
12. Click "Save". Save it to the desktop.

Create a Backup of the Template GPO
1. Launch GPMC.
2. Expand "Group Policy Objects".
3. Right-Click "Group Policy Objects" \ Choose the policy you created above.
4. R-CLick the group policy \ Choose "Back Up...".
5. Click "Browse" \ Find the directory you stored the migration table in.
6. Click "Back Up".
7. Confirm it was successful.
8. Click OK.
9. Exit GPMC.
10. Locate the backup wherever you stored it and open its folder in File Explorer.
	Backed Up GPOs have a GUID for their folder name.
11. Right-Click in the space after "gpreport" \ New "Text Document".
12. Rename the text document after the policy name. This is for ease of use searching later. 
13. In file explorer, go back one level to the folder with the GPO folder and the migration table. 
11. Zip the two files together and save the Zip as the name of the GPO. Store this for distribution.

Modify the Migration Table
1. Launch GPMC.
2. Expand "Group Policy Objects".
3. Right-Click "Group Policy Objects" \ Choose "Open Migration Table Editor".
4. File \ Open \ Locate the migration table.
5. Change the relevent "Destination Name" fields to the name of the in-domain group you are trying to grant access to.
6. File \ Save.
7. Exit the Migration Table Editor. 

Import a GPO (Manual Steps)
1. Launch GPMC.
2. 2. Expand "Group Policy Objects".
3. Right-Click "Group Policy Objects" \ New
4. Specify a name of the new policy. (e.g., User Rights - Test Servers Policy".
5. Locate the new GPO under "Group Policy Objects".
6. Right-Click the policy \ Choose "Import Settings".
7. Click NEXT.
8. If you're doing this on a production policy or one whose settings you don't want to lose, back up the existing GPO. Otherwise, click NEXT.
9. Browse to the backup folder. You only need to go to the directory the whole GPO backup folder is on.
10. Click NEXT.
11. Find and choose the correct backed up GPO. 
12. Click NEXT.
13. Click NEXT.
14. On the "Migrating References" page, choose "Using this migration table to map them in the destinaton GPO"
15. Browse to the location of the migration table. 
	It will default to the same parent folder as the backup. (This is why I store them side by side). 
16. Click NEXT.
17. Click FINSIH.
18. Wait for settings to import.
19. Click NEXT.
20. In GPMC, review the settings of the GPO you just imported onto. It should have all the settings with the migration table data and the "Details \ GPO Status" should reflect correctly. 

16. 
-->
