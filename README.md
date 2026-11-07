# Intune Local Groups GUI — WPF v2.1

Run `Start-GUI.cmd` on Windows with `MainWindow.xaml` beside the script. Use **Install / repair module**, then **Sign in / switch account**. Authentication uses the Microsoft account window and the app-private Graph Authentication 2.39.0 workaround.

## Group search

Under Configure, expand **Search Entra groups (Graph)**. Enter the beginning of a group name, search, select a result and a destination, and add it. Results include both user and device groups; verify the selected group's membership. Names must resolve uniquely during preview. Inform API integration is pending its endpoint, authentication scheme and response documentation.

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
