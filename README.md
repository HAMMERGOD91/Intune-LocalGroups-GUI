# Intune Local Groups GUI — WPF v2.2

Run `Start-GUI.cmd` on Windows with `MainWindow.xaml` and `CoeGroups.ps1` beside the script. Use **Install / repair module**, then **Sign in / switch account**. Authentication uses the Microsoft account window and the app-private Graph Authentication 2.39.0 workaround.

## COE group search and automatic placement

Expand **Search COE groups (Graph)**. Search is limited to names beginning with `COE-`. Search fragments are case-insensitive and matched in order, allowing intervening text. Hyphens, spaces and asterisks separate fragments. For example, `mg-baas` or `* mg-baas *` matches `COE-ECE-MG-Research-Baas-Admins`; `dg-baas` matches the corresponding device group. All pages of COE groups are retrieved before local matching; searches may take longer in large directories.

Use Ctrl+click to select several results, then **Add selected groups automatically**:

| Name convention | Destination |
| --- | --- |
| COE-<DEPT>-MG-...-Admins | Administrators |
| COE-<DEPT>-MG-... without -Admins | Both Users and RDP |
| COE-<DEPT>-DG-... | Device targets |

MG groups must be security groups. DG routing uses your naming convention; verify device membership. Unsupported naming patterns are rejected for automatic placement. Duplicate names are not added twice. Exact duplicate Entra display names still block resolution during preview.

## COE defaults and generated policy names

Configure fixes the local administrator to `coeit` and scope tag to `COE`. The default description identifies the PowerShell GUI. Verify that coeit is the actual built-in administrator name on the targets.

Names are generated from COE department, MG/DG, and the remaining name, removing a trailing -Admins:

| Example group | Policy name |
| --- | --- |
| COE-ECE-MG-Research-Baas-Admins | COE-ECE: Set User Groups (Research-Baas) |
| COE-ECE-DG-Research-Baas | COE-ECE: Set User Groups (Research-Baas) |
| COE-CEE-MG-Admin-Staff | COE-CEE: Set User Groups (Admin-Staff) |
| COE-MSE-MG-Faculty-Takamura | COE-MSE: Set User Groups (Faculty-Takamura) |

Adding, changing or removing source/target entries recalculates the name. If groups imply several policy names, the name is cleared; remove unrelated groups or manually enter the intended name. This prevents silently taking the last selected department or PI. Existing-policy editing retains the loaded XML, name, scope tags and assignments until explicitly edited; Configure defaults do not rewrite existing XML.

Inform integration is no longer needed.

## Existing policies

Open **Existing policies**, list custom policies, select one and load it. This editor supports dedicated LocalUsersAndGroups custom XML policies, not Settings Catalog or endpoint-security profiles. Edit the name, description and XML, click **Preview existing edit**, review it, then **Save existing policy**. Scope tags and assignments are preserved. A JSON backup is saved before updating, and changes detected since loading block the save.

Expanded RDP user SIDs cannot reveal their original source group names. Existing membership is therefore edited as XML rather than guessed source groups. XML structural checks do not guarantee device-side acceptance.

## Creating policies

Configure the local administrator, scope tag, source groups and device targets. Use **Resolve and preview**, then **Apply policy**. Restrict actions replace local membership. Verify the built-in administrator name on every target. This does not create or enable accounts. RDP expansion is a snapshot. Existing assignments are preserved and requested groups added; scope tags are replaced with the selected tag.

## Logs and updates

Logs, XML previews and backups: `C:\temp\Intune Script Logs`.

Close the GUI and use **Git: Pull** in VS Code to retrieve changes, then run `Start-GUI.cmd` again.

## Validation

XAML structure and UI control references checked. Windows rendering, PowerShell execution and live tenant operations have not been tested in the delivery environment. Test with a dedicated device group.
