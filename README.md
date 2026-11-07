# Intune-LocalGroups-GUI — WPF v2.0

PowerShell GUI for managing Intune local group policies.

## Start

1. Clone this repository to Windows using GitHub Desktop.
2. Double-click `Start-GUI.cmd`. Keep `MainWindow.xaml` beside the PowerShell script.
3. Select **Install / repair module**, then **Sign in / switch account**.
4. Enter your groups, select **Resolve and preview**, and review before applying.

Version 2.0 uses an app-private copy of Microsoft.Graph.Authentication 2.39.0 as a workaround for reported RefreshCacheAsync failures in 2.41.x.

**This policy replaces local group membership.** Verify the local administrator and device targets before applying. Windows sign-in and live Intune operations still require validation in your environment.

See [README.txt](README.txt) for full setup, authentication options, policy behavior and limitations.

## WPF interface

- **Configure**: policy details, source groups and device targets.
- **Review**: resolved policy summary and XML before applying.
- **Activity**: progress and error messages.

The window is defined in `MainWindow.xaml`; PowerShell handles events and Graph operations in a separate STA runspace. A WPF DispatcherTimer updates the interface.

XAML XML structure and control-name references were checked. This environment cannot execute Windows WPF or verify tenant sign-in.

## Update your local copy

Close the GUI. In GitHub Desktop, select this repository, click **Fetch origin**, then **Pull origin** when available. Reopen `Start-GUI.cmd`.
