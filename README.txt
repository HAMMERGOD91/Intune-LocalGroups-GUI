WPF v2.0
The interface is now Windows Presentation Foundation, defined in MainWindow.xaml.
Keep that file beside Intune-LocalGroups-GUI.ps1 and Start-GUI.cmd.
Configure contains policy/group inputs; Review contains resolved XML and targets;
Activity contains operation messages. Graph operations run in an STA worker
runspace, with UI updates handled by a WPF DispatcherTimer.
The Graph Authentication 2.39.0 workaround from v1.1 is retained.
XAML XML structure and controller-name references were checked. Windows WPF
rendering, PowerShell execution and tenant authentication were not tested here.

AUTHENTICATION REPAIR IN v1.1
The same RefreshCacheAsync error has been reported against Graph 2.41.x:
https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3816
That report concerns certificate sign-in and reports 2.39 or lower working;
it is evidence for this workaround, not proof of your exact failure cause.

This GUI now uses ONLY its app-private version 2.39.0, imported by full path:
%LOCALAPPDATA%\IntuneLocalGroupsGUI\Modules
It also starts a clean, profile-free PowerShell process even when invoked
from an existing console. DLLs cannot reliably be unloaded with Remove-Module.

To use this revision:
1. Close the old GUI.
2. Extract this ZIP into a new folder and launch Start-GUI.cmd.
3. Confirm the window title ends in WPF v2.0.
4. Select Install / repair module, then Sign in / switch account.
5. Leave Use web browser unchecked for the usual Microsoft account window.
Repairing a module after it has been loaded requires closing and reopening
the GUI first. The activity log records the exact module path and version.
This workaround has not been executed on Windows in the delivery environment.

INTUNE LOCAL GROUP POLICY GUI v2.0 (WPF)

GET STARTED
1. Extract the ZIP into a folder on a Windows computer.
2. Double-click Start-GUI.cmd. PowerShell 7 is recommended; Windows
   PowerShell 5.1 is also supported. Run as your normal interactive account.
   Do not deploy this GUI through Intune/BigFix or run it as SYSTEM.
3. Select Install / repair module BEFORE signing in. This downloads an
   app-private copy of Microsoft.Graph.Authentication version 2.39.0.
   Existing Graph modules are not changed or uninstalled.
   Internet access to PowerShell Gallery is needed. If your organization's
   policy blocks installation, have IT install the module. The application
   does not bypass execution policy. Your organization may require signing
   the script or unblocking the downloaded files.
4. Select Sign in / switch account. Complete Microsoft's sign-in window,
   including MFA or consent when required. Check the taskbar if it opens
   behind the GUI. The GUI never asks for or stores your password.
5. Confirm the signed-in account and tenant in the activity log. Tenant ID
   is optional for ordinary Microsoft account-window sign-in; entering it
   is recommended when you administer multiple tenants.
6. Enter the policy name, description, existing local administrator name,
   scope tag, and group names. Use ONE EXACT GROUP DISPLAY NAME PER LINE.
   Duplicate or missing group-name matches stop the operation.
   Administrator and Users source groups must be security groups.
   Enter device-containing groups in Device target groups. The tool resolves
   the group but cannot guarantee that its membership contains only devices.
7. Select Resolve and preview. Review the tenant, policy, device targets,
   RDP user count and full XML. This step does not change Intune.
8. Select Apply policy and review the confirmation. Devices receive the
   change on a subsequent Intune sync; a successful save does not prove
   successful application on every device.

MICROSOFT SIGN-IN WINDOW VS. WEB BROWSER
The default uses Connect-MgGraph interactive delegated authentication,
with process-scoped authentication and no device-code login. On current
Windows Graph versions this is normally Microsoft's Web Account Manager
account window. Microsoft may reuse Windows SSO; a password prompt is
controlled by Microsoft and your tenant, not forced by this application.
Sign in / switch account disconnects the current Graph context first.

If you specifically require sign-in in a WEB BROWSER, check Use web browser
and enter both Tenant ID and your CUSTOM public client App client ID.
Current Graph versions do not allow disabling WAM for the default Graph
PowerShell client. A custom app is therefore necessary for this option.
The tool temporarily disables WAM for connection, then restores the option.

Custom app setup (performed by your Entra administrator):
- Register a single-tenant app in Microsoft Entra ID.
- Add the Mobile and desktop applications platform and redirect URI
  http://localhost for system-browser interactive authentication.
- Enable public client flows as required for your app configuration.
- Add delegated Microsoft Graph permissions listed below, and grant
  administrator consent according to your organization's policy.
- No client secret or certificate is needed.

REQUIRED DELEGATED PERMISSIONS
GroupMember.Read.All
User.Read.All
DeviceManagementConfiguration.ReadWrite.All
DeviceManagementRBAC.Read.All

Your signed-in account must also have the appropriate Intune RBAC rights,
scope-tag access and an appropriately licensed tenant. Consent alone does
not grant an operator the necessary Intune role. Hidden group memberships
can require additional permissions; this GUI does not request those.
Only the Microsoft public/global cloud is supported by this version.

POLICY BEHAVIOR (READ BEFORE APPLYING)
- Preserves the original script's R/Restrict behavior for Administrators,
  Users and Remote Desktop Users: current membership is REPLACED.
- Verify the Local admin field is the actual BUILT-IN administrator account
  name (including any rename) on EVERY target. A separate custom admin
  named itadmin01 does not satisfy the requirement to retain the built-in
  administrator. This tool cannot check local accounts on target devices
  and does not create/enable accounts. An incorrect name can cause failure
  or loss of access. Test on a dedicated device group first.
- Administrators and Users receive Entra group SIDs, not expanded users.
- RDP source groups are recursively expanded into individual user SIDs,
  deduplicated, with UPN comments. This is a SNAPSHOT; rerun when source
  membership changes. Enabling RDP/firewall access is outside this policy.
- Blank source lists are allowed: Administrators/Users then contain only
  the specified local admin; Remote Desktop Users becomes empty.
- Built-in local group SIDs avoid localized group-name mismatches.
- Uses XML DOM APIs to escape member values and sanitize audit comments.
- Creates a dedicated Windows custom configuration or updates the unique
  policy with the exact name. Refuses to update a different policy type or
  a policy containing unrelated OMA settings. Uses Graph beta for scope tags.
- Scope tags are set to the one requested tag; existing tags are replaced.
- Existing assignments (including exclusions/filters) are retained, and
  selected target groups are added. The tool does not remove old targets.
  Inspect existing Intune assignments before updating a policy. An existing
  exclusion for a selected target blocks Apply.
- Existing policy JSON and assignments are backed up before update. A
  last-modified check rejects detected changes since preview; there is no
  transaction or automatic rollback. Avoid simultaneous policy edits.
- Policy save and assignment are separate Graph operations. If assignment
  fails, the saved policy remains. Inspect Intune, preview and retry.
- Avoid assigning competing LocalUsersAndGroups/RestrictedGroups policies.

LOGS AND BACKUPS
C:\temp\Intune Script Logs
Contains activity logs, preview XML, and JSON backups of updated policies.
These can include user UPNs and group names. Passwords/tokens are not logged.
Use Open logs to open the folder. Backups are reference exports; there is no
one-click restore. Creating files here must be permitted for your account.

VALIDATION
Reviewed for input handling, Graph paging, exact-name resolution, XML
escaping, assignment preservation, preview invalidation and error paths.
The delivery environment has no Windows desktop or PowerShell runtime.
The GUI, Microsoft authentication, and live Graph operations have NOT been
executed here. Validate with your tenant and a test group before production.

REFERENCES
https://github.com/microsoftgraph/msgraph-sdk-powershell/blob/main/docs/authentication.md
https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/connect-mggraph
https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/set-mggraphoption
https://learn.microsoft.com/windows/client-management/mdm/policy-csp-localusersandgroups
