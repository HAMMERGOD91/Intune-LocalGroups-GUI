#requires -Version 5.1
<#
.SYNOPSIS
Windows GUI for creating/updating an Intune LocalUsersAndGroups custom policy.
.NOTES
Run interactively as the operator, never as SYSTEM. PowerShell 7 recommended.
Requires Microsoft.Graph.Authentication (install offered through the GUI).
Uses Microsoft-hosted authentication; passwords/tokens are never collected by this GUI.
#>
[CmdletBinding()]
param([switch]$CleanSession)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This GUI requires Windows.' }
if (-not $CleanSession -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    # Always start a clean process: Remove-Module cannot unload conflicting DLLs.
    $exe = (Get-Process -Id $PID).Path
    if ([IO.Path]::GetFileNameWithoutExtension($exe) -notin @('pwsh','powershell')) {
        $exe = (Get-Command powershell.exe -ErrorAction Stop).Source
    }
    Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-STA','-File',('"{0}"' -f $PSCommandPath),'-CleanSession')
    return
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$script:logDir = 'C:\temp\Intune Script Logs'
New-Item -ItemType Directory -Path $script:logDir -Force | Out-Null
$script:logFile = Join-Path $script:logDir ('LocalGroupsGUI_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
$script:queue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:state = [hashtable]::Synchronized(@{ Connected = $false; Plan = $null })
$script:runspace = [RunspaceFactory]::CreateRunspace()
$script:runspace.ApartmentState = 'STA'
$script:runspace.ThreadOptions = 'ReuseThread'
$script:runspace.Open()
$script:job = $null
$script:worker = {
    param($Operation, $Config, $Queue, $State, $LogDir)
    $ErrorActionPreference = 'Stop'
    # 2.41.x has reports of RefreshCacheAsync type-load failures (SDK issue 3816).
    # Use an app-private copy rather than downgrading the operator's other modules.
    $authVersion = '2.39.0'
    $moduleRoot = Join-Path $env:LOCALAPPDATA 'IntuneLocalGroupsGUI\Modules'
    $authFolder = Join-Path $moduleRoot "Microsoft.Graph.Authentication\$authVersion"
    $authManifest = Join-Path $authFolder 'Microsoft.Graph.Authentication.psd1'
    function Report([string]$Text) { $Queue.Enqueue(@{ Kind = 'Log'; Text = $Text }) }
    function Graph([string]$Method, [string]$Uri, $Body = $null) {
        $p = @{ Method = $Method; Uri = $Uri; OutputType = 'Hashtable'; ErrorAction = 'Stop' }
        if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Depth 50); $p.ContentType = 'application/json' }
        Invoke-MgGraphRequest @p
    }
    function All([string]$Uri) {
        do {
            $page = Graph GET $Uri
            foreach ($item in $page.value) { $item }
            $Uri = $page['@odata.nextLink']
        } while ($Uri)
    }
    function FindGroup([string]$Name) {
        $filter = [Uri]::EscapeDataString("displayName eq '$($Name.Replace("'", "''"))'")
        $items = @(All "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,securityEnabled,securityIdentifier")
        if ($items.Count -ne 1) { throw "Group '$Name': found $($items.Count) matches. An exact, unique display name is required." }
        Report "Resolved group: $Name [$($items[0].id)]"
        return $items[0]
    }
    function Sid([string]$Id) {
        $bytes = ([guid]$Id).ToByteArray()
        $parts = for ($i = 0; $i -lt 16; $i += 4) { [BitConverter]::ToUInt32($bytes,$i) }
        'S-1-12-1-' + ($parts -join '-')
    }
    function AddMembers($Document, $Root, [string]$GroupSid, $Members) {
        $access = $Document.CreateElement('accessgroup'); $access.SetAttribute('desc',$GroupSid)
        [void]$Root.AppendChild($access)
        $action = $Document.CreateElement('group'); $action.SetAttribute('action','R'); [void]$access.AppendChild($action)
        foreach ($m in $Members) {
            $add = $Document.CreateElement('add'); $add.SetAttribute('member',[string]$m.SID); [void]$access.AppendChild($add)
            $label = ([string]$m.Label).Replace('--','- -')
            if ($label.EndsWith('-')) { $label += ' ' }
            [void]$access.AppendChild($Document.CreateComment(" $label "))
        }
    }
    try {
        switch ($Operation) {
            'Install' {
                if ($State.ModuleLoaded) { throw 'Close this GUI, reopen it, then select Install / repair module BEFORE signing in. Loaded authentication DLLs require a fresh process.' }
                Report "Installing app-private Microsoft.Graph.Authentication $authVersion..."
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -Confirm:$false | Out-Null
                }
                $stage = Join-Path $moduleRoot ('staging_' + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $stage -Force | Out-Null
                Save-Module -Name Microsoft.Graph.Authentication -RequiredVersion $authVersion -Repository PSGallery -Path $stage -Force -Confirm:$false
                $stagedFolder = Join-Path $stage "Microsoft.Graph.Authentication\$authVersion"
                $manifest = Test-ModuleManifest -Path (Join-Path $stagedFolder 'Microsoft.Graph.Authentication.psd1')
                if ($manifest.Version -ne [version]$authVersion) { throw 'Downloaded module version does not match the requested version.' }
                if (Test-Path -LiteralPath $authFolder) {
                    Move-Item -LiteralPath $authFolder -Destination ($authFolder + '_backup_' + [guid]::NewGuid().ToString('N'))
                }
                New-Item -ItemType Directory -Path (Split-Path $authFolder) -Force | Out-Null
                Move-Item -LiteralPath $stagedFolder -Destination $authFolder
                Report "App-private module $authVersion installed. Select Sign in. Your other Graph installations were not changed."
            }
            'Connect' {
                $State.Plan = $null; $State.Connected = $false
                if (-not (Test-Path -LiteralPath $authManifest)) {
                    throw 'Select Install / repair module first to download the app-private authentication module.'
                }
                $State.ModuleLoaded = $true
                Import-Module -Name $authManifest -ErrorAction Stop
                Report "Authentication module: $authVersion | $authManifest | PowerShell $($PSVersionTable.PSVersion)"
                if (Get-MgContext) { Disconnect-MgGraph | Out-Null }
                $p = @{
                    Scopes = @('GroupMember.Read.All','User.Read.All','DeviceManagementConfiguration.ReadWrite.All','DeviceManagementRBAC.Read.All')
                    ContextScope = 'Process'; NoWelcome = $true; ErrorAction = 'Stop'
                }
                if ($Config.Tenant) { $p.TenantId = $Config.Tenant }
                if ($Config.Client) { $p.ClientId = $Config.Client }
                $previousWamOption = (Get-MgGraphOption).DisableLoginByWAM
                if ($Config.Browser) {
                    if (-not $Config.Client -or -not $Config.Tenant) { throw 'Browser sign-in requires both a custom app client ID and tenant ID.' }
                    Set-MgGraphOption -DisableLoginByWAM $true | Out-Null
                    Report 'Opening Microsoft sign-in in your web browser. Complete sign-in there.'
                } else {
                    Set-MgGraphOption -DisableLoginByWAM $false | Out-Null
                    Report 'Opening Microsoft interactive sign-in. Check the taskbar if the account window is behind this app.'
                }
                try { Connect-MgGraph @p | Out-Null }
                finally { Set-MgGraphOption -DisableLoginByWAM $previousWamOption | Out-Null }
                $context = Get-MgContext
                if (-not $context -or $context.AuthType -ne 'Delegated') { throw 'An interactive work or school account connection is required.' }
                $State.Connected = $true
                $State.Account = $context.Account; $State.Tenant = $context.TenantId
                Report "Connected: $($context.Account) | Tenant: $($context.TenantId)"
            }
            'Preview' {
                $State.Plan = $null
                if (-not $State.Connected) { throw 'Sign in first.' }
                $admin = @(@{ SID = $Config.Admin; Label = 'Preserved local administrator (must exist on every target)' })
                $users = @(@{ SID = $Config.Admin; Label = 'Preserved local administrator' })
                foreach ($name in $Config.AdminGroups) {
                    $g = FindGroup $name
                    if (-not $g.securityEnabled) { throw "Administrator source '$name' must be a security group." }
                    $admin += @{ SID = (Sid $g.id); Label = $g.displayName }
                }
                foreach ($name in $Config.UserGroups) {
                    $g = FindGroup $name
                    if (-not $g.securityEnabled) { throw "Users source '$name' must be a security group." }
                    $users += @{ SID = (Sid $g.id); Label = $g.displayName }
                }
                $rdp = @{}
                foreach ($name in $Config.RdpGroups) {
                    $g = FindGroup $name
                    $members = @(All "https://graph.microsoft.com/v1.0/groups/$($g.id)/transitiveMembers/microsoft.graph.user?`$select=id,userPrincipalName&`$top=999")
                    foreach ($m in $members) {
                        if (-not $m.userPrincipalName) { throw "Cannot read UPN for user $($m.id). Check permissions and group membership visibility." }
                        $rdp[$m.id] = @{ SID = (Sid $m.id); Label = $m.userPrincipalName }
                    }
                    Report "Expanded RDP group '$name': $($members.Count) users."
                }
                $targets = @(); foreach ($name in $Config.Targets) { $targets += FindGroup $name }
                $tags = @(All 'https://graph.microsoft.com/beta/deviceManagement/roleScopeTags' | Where-Object { $_.displayName -eq $Config.Tag })
                if ($tags.Count -ne 1) { throw "Scope tag '$($Config.Tag)': found $($tags.Count) matches." }
                $filter = [Uri]::EscapeDataString("displayName eq '$($Config.Name.Replace("'", "''"))'")
                $existing = @(All "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=$filter")
                if ($existing.Count -gt 1) { throw 'Multiple policies have this name. Use a unique policy name.' }
                if ($existing.Count -eq 1) {
                    $existing = @(Graph GET "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($existing[0].id)")
                    if ($existing[0]['@odata.type'] -ne '#microsoft.graph.windows10CustomConfiguration') { throw 'The existing policy is not a Windows custom configuration.' }
                    # Avoid resubmitting encrypted/unrelated settings with unreadable values.
                    $others = @($existing[0].omaSettings | Where-Object { $_.omaUri -ne './Device/Vendor/MSFT/Policy/Config/LocalUsersAndGroups/Configure' })
                    if ($others.Count) { throw 'The existing policy contains unrelated OMA settings. Use a separate, dedicated policy name.' }
                }
                $doc = [xml]::new(); $root = $doc.CreateElement('GroupConfiguration'); [void]$doc.AppendChild($root)
                AddMembers $doc $root 'S-1-5-32-544' $admin
                AddMembers $doc $root 'S-1-5-32-545' $users
                AddMembers $doc $root 'S-1-5-32-555' @($rdp.Values | Sort-Object Label)
                $sw = [IO.StringWriter]::new(); $settings = [Xml.XmlWriterSettings]::new()
                $settings.Indent = $true; $settings.OmitXmlDeclaration = $true
                $writer = [Xml.XmlWriter]::Create($sw,$settings); $doc.Save($writer); $writer.Dispose()
                $xml = $sw.ToString(); $sw.Dispose()
                $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
                $xmlPath = Join-Path $LogDir "LocalGroups_Preview_$stamp.xml"
                [IO.File]::WriteAllText($xmlPath,$xml,[Text.UTF8Encoding]::new($false))
                $id = $null; $version = $null
                if ($existing.Count) { $id = $existing[0].id; $version = $existing[0].lastModifiedDateTime }
                $State.Plan = @{ Config = $Config; Xml = $xml; Targets = $targets; Tag = [string]$tags[0].id; Id = $id; Version = $version; Existing = $existing; Stamp = $stamp }
                $action = 'CREATE'; if ($id) { $action = "UPDATE $id" }
                $summary = "$action`r`nAccount: $($State.Account)`r`nTenant: $($State.Tenant)`r`nPolicy: $($Config.Name)`r`nScope tag: $($Config.Tag)`r`nTargets: $($Config.Targets -join ', ')`r`nRDP users: $($rdp.Count)`r`n`r`nREPLACE membership for Administrators, Users, and Remote Desktop Users.`r`nExisting Intune assignments are preserved; requested groups are added.`r`nRDP expansion is a snapshot; rerun after membership changes.`r`n`r`n$xml"
                $Queue.Enqueue(@{ Kind = 'Preview'; Text = $summary })
                Report "Preview ready; no Intune changes made. XML: $xmlPath"
            }
            'Apply' {
                $plan = $State.Plan
                if (-not $State.Connected -or -not $plan) { throw 'Sign in and generate a new preview first.' }
                $State.Plan = $null
                $base = 'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations'
                $assignments = @()
                if ($plan.Id) {
                    $fresh = Graph GET "$base/$($plan.Id)"
                    if ($fresh.lastModifiedDateTime -ne $plan.Version) { throw 'The policy changed since preview. Generate a new preview.' }
                    $oldAssignments = @(All "$base/$($plan.Id)/assignments")
                    foreach ($a in $oldAssignments) { $assignments += @{ target = $a.target } }
                    $backup = @{ Policy = $fresh; Assignments = $oldAssignments }
                    $backupPath = Join-Path $LogDir "LocalGroups_Backup_$($plan.Stamp).json"
                    [IO.File]::WriteAllText($backupPath,($backup | ConvertTo-Json -Depth 50),[Text.UTF8Encoding]::new($false))
                    Report "Existing policy and assignments backed up: $backupPath"
                } else {
                    $filter = [Uri]::EscapeDataString("displayName eq '$($plan.Config.Name.Replace("'", "''"))'")
                    if (@(All "$base`?`$filter=$filter").Count) { throw 'A policy with this name now exists. Generate a new preview.' }
                }
                foreach ($g in $plan.Targets) {
                    $present = @($assignments | Where-Object { $_.target['@odata.type'] -eq '#microsoft.graph.groupAssignmentTarget' -and $_.target.groupId -eq $g.id -and -not $_.target.deviceAndAppManagementAssignmentFilterId })
                    $excluded = @($assignments | Where-Object { $_.target['@odata.type'] -eq '#microsoft.graph.exclusionGroupAssignmentTarget' -and $_.target.groupId -eq $g.id })
                    if ($excluded.Count) { throw "Target '$($g.displayName)' is currently excluded. Resolve the exclusion in Intune first." }
                    if (-not $present.Count) { $assignments += @{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $g.id } } }
                }
                $body = @{
                    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
                    displayName = $plan.Config.Name; description = $plan.Config.Description
                    roleScopeTagIds = @($plan.Tag)
                    omaSettings = @(@{
                        '@odata.type' = '#microsoft.graph.omaSettingStringXml'
                        displayName = 'LocalGroupsConfig'; description = 'Managed via PowerShell GUI'
                        omaUri = './Device/Vendor/MSFT/Policy/Config/LocalUsersAndGroups/Configure'
                        fileName = 'localgroups.xml'; value = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plan.Xml))
                    })
                }
                $id = $plan.Id
                if ($id) {
                    Report "Updating policy $id..."
                    Graph PATCH "$base/$id" $body | Out-Null
                } else {
                    Report 'Creating policy...'
                    $new = Graph POST $base $body; $id = $new.id
                    if (-not $id) { throw 'Create did not return a policy ID. Inspect Intune before retrying.' }
                }
                Report "Policy saved: $id. Applying assignments..."
                try { Graph POST "$base/$id/assign" @{ assignments = @($assignments) } | Out-Null }
                catch { throw "Policy $id was saved, but assignment failed: $($_.Exception.Message). Inspect Intune and preview again before retrying." }
                Report "Complete. Policy ID: $id. Device application occurs at a later Intune sync."
                $Queue.Enqueue(@{ Kind = 'Success'; Text = "Policy saved and assigned.`r`nPolicy ID: $id" })
            }
            'Disconnect' {
                if (Get-Command Get-MgContext -ErrorAction SilentlyContinue) { if (Get-MgContext) { Disconnect-MgGraph | Out-Null } }
                $State.Connected = $false; $State.Plan = $null
                Report 'Disconnected.'
            }
        }
    } catch {
        if ($Operation -eq 'Connect') { $State.Connected = $false }
        if ($_.Exception.ToString() -match 'RefreshCacheAsync|Could not load file or assembly|does not have an implementation') {
            Report 'Authentication DLL compatibility failure. Close this GUI, relaunch Start-GUI.cmd, then select Install / repair module before signing in.'
            foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -match 'Microsoft.Graph.Authentication|Microsoft.Identity.Client|Azure.Identity' }) {
                Report "Loaded assembly: $($assembly.FullName) | $($assembly.Location)"
            }
        }
        $Queue.Enqueue(@{ Kind = 'Error'; Text = $_.Exception.Message })
    }
}

$xamlPath = Join-Path $PSScriptRoot 'MainWindow.xaml'
if (-not (Test-Path -LiteralPath $xamlPath)) { throw "Missing WPF layout: $xamlPath. Keep MainWindow.xaml beside this script." }
$reader = [Xml.XmlReader]::Create($xamlPath)
try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
$ui = @{}
foreach ($controlName in @('AuthInputs','TenantBox','ClientBox','BrowserCheck','InstallButton','ConnectButton','DisconnectButton','AccountText','Tabs','ConfigureTab','ReviewTab','ActivityTab','PolicyInputs','NameBox','DescriptionBox','AdminBox','TagBox','AdminGroupsBox','UserGroupsBox','RdpGroupsBox','TargetsBox','PreviewBox','ActivityBox','BusyBar','LogsButton','PreviewButton','ApplyButton','StatusText')) {
    $ui[$controlName] = $window.FindName($controlName)
}
$script:mutable = @($ui.AuthInputs,$ui.BrowserCheck,$ui.PolicyInputs,$ui.InstallButton,$ui.ConnectButton,$ui.DisconnectButton,$ui.PreviewButton)
function Log([string]$Text) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'),$Text
    $ui.ActivityBox.AppendText($line + "`r`n")
    $ui.ActivityBox.ScrollToEnd()
    Add-Content -LiteralPath $script:logFile -Value $line -Encoding UTF8
}
function Names($Control) { @($Control.Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique) }
function Config {
    @{
        Tenant = $ui.TenantBox.Text.Trim(); Client = $ui.ClientBox.Text.Trim(); Browser = [bool]$ui.BrowserCheck.IsChecked
        Name = $ui.NameBox.Text.Trim(); Description = $ui.DescriptionBox.Text.Trim(); Admin = $ui.AdminBox.Text.Trim(); Tag = $ui.TagBox.Text.Trim()
        AdminGroups = @(Names $ui.AdminGroupsBox); UserGroups = @(Names $ui.UserGroupsBox); RdpGroups = @(Names $ui.RdpGroupsBox); Targets = @(Names $ui.TargetsBox)
    }
}
function Notice([string]$Text,[string]$Title = 'Intune local groups',[string]$Icon = 'Information') {
    [void][Windows.MessageBox]::Show($window,$Text,$Title,[Windows.MessageBoxButton]::OK,[Windows.MessageBoxImage]$Icon)
}
function Refresh-Controls {
    foreach ($c in $script:mutable) { $c.IsEnabled = $true }
    $ui.ApplyButton.IsEnabled = $script:state.Connected -and ($null -ne $script:state.Plan)
    $ui.BusyBar.Visibility = 'Collapsed'
    if ($script:state.Connected) { $ui.AccountText.Text = "$($script:state.Account) | Tenant: $($script:state.Tenant)" }
    else { $ui.AccountText.Text = 'Not connected' }
}
function Start-Work([string]$Operation) {
    if ($script:job) { return }
    $config = Config
    if ($Operation -eq 'Preview') {
        if (-not $config.Name -or -not $config.Admin -or -not $config.Tag -or -not $config.Targets.Count) {
            Notice 'Enter a policy name, local administrator, scope tag, and at least one device target group.' 'Required fields' 'Warning'; return
        }
        if ($config.Admin -match '[\\/@]') { Notice 'Use the existing local administrator account name, without a domain or UPN.' 'Local account required' 'Warning'; return }
    }
    foreach ($c in $script:mutable) { $c.IsEnabled = $false }
    $ui.ApplyButton.IsEnabled = $false; $ui.BusyBar.Visibility = 'Visible'
    $ui.StatusText.Text = "$Operation in progress..."
    $ps = [PowerShell]::Create(); $ps.Runspace = $script:runspace
    try {
        [void]$ps.AddScript($script:worker.ToString()).AddArgument($Operation).AddArgument($config).AddArgument($script:queue).AddArgument($script:state).AddArgument($script:logDir)
        $script:job = @{ PS = $ps; Handle = $ps.BeginInvoke(); Operation = $Operation; Failed = $false }
    } catch {
        $ps.Dispose(); $script:job = $null; Refresh-Controls
        Log "ERROR: $($_.Exception.Message)"; Notice $_.Exception.Message 'Could not start operation' 'Error'
    }
}
function Invalidate-Preview {
    $script:state.Plan = $null; $ui.ApplyButton.IsEnabled = $false
    $ui.PreviewBox.Text = 'Inputs changed. Resolve and preview again before applying.'
    $ui.StatusText.Text = 'Ready to resolve and preview.'
}
foreach ($c in @($ui.NameBox,$ui.DescriptionBox,$ui.AdminBox,$ui.TagBox,$ui.AdminGroupsBox,$ui.UserGroupsBox,$ui.RdpGroupsBox,$ui.TargetsBox)) {
    $c.Add_TextChanged({ Invalidate-Preview })
}
$authChanged = {
    Invalidate-Preview; $script:state.Connected = $false
    $ui.AccountText.Text = 'Sign in to use changed authentication settings'
}
$ui.TenantBox.Add_TextChanged($authChanged); $ui.ClientBox.Add_TextChanged($authChanged)
$ui.BrowserCheck.Add_Checked($authChanged); $ui.BrowserCheck.Add_Unchecked($authChanged)
$ui.InstallButton.Add_Click({ Start-Work 'Install' })
$ui.ConnectButton.Add_Click({ Start-Work 'Connect' })
$ui.DisconnectButton.Add_Click({ Start-Work 'Disconnect' })
$ui.PreviewButton.Add_Click({ Start-Work 'Preview' })
$ui.LogsButton.Add_Click({ Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:logDir) })
$ui.ApplyButton.Add_Click({
    if (-not $script:state.Plan) { return }
    $p = $script:state.Plan
    $message = "Apply '$($p.Config.Name)' in tenant $($script:state.Tenant)?`r`n`r`nThis REPLACES membership of Administrators, Users, and Remote Desktop Users on assigned devices. Members absent from the preview can be removed.`r`n`r`nVerify '$($p.Config.Admin)' is the actual built-in administrator name on EVERY target device. This policy does not create or enable it.`r`n`r`nScope tags will be set to '$($p.Config.Tag)'. Existing assignments are kept and selected targets added.`r`n`r`nEmpty RDP sources clear that group's membership. RDP users are a snapshot, not a live group link."
    if ([Windows.MessageBox]::Show($window,$message,'Apply Intune policy',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Warning,[Windows.MessageBoxResult]::No) -eq [Windows.MessageBoxResult]::Yes) { Start-Work 'Apply' }
})
function Drain-Events {
    $item = $null
    while ($script:queue.TryDequeue([ref]$item)) {
        switch ($item.Kind) {
            'Log' { Log $item.Text }
            'Preview' { $ui.PreviewBox.Text = $item.Text; $ui.Tabs.SelectedItem = $ui.ReviewTab }
            'Error' {
                if ($script:job) { $script:job.Failed = $true }
                Log "ERROR: $($item.Text)"; $ui.Tabs.SelectedItem = $ui.ActivityTab
                Notice $item.Text 'Operation failed' 'Error'
            }
            'Success' { Notice $item.Text 'Complete' }
        }
        $item = $null
    }
}
$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:inTick = $false
$timer.Add_Tick({
    if ($script:inTick) { return }
    $script:inTick = $true
    try {
        Drain-Events
        if ($script:job -and $script:job.Handle.IsCompleted) {
            try {
                $script:job.PS.EndInvoke($script:job.Handle) | Out-Null
                foreach ($e in $script:job.PS.Streams.Error) { $script:job.Failed = $true; Log "ERROR: $e" }
            } catch { $script:job.Failed = $true; Log "ERROR: $($_.Exception.Message)" }
            finally {
                Drain-Events
                $operation = $script:job.Operation; $failed = $script:job.Failed
                $script:job.PS.Dispose(); $script:job = $null
                Refresh-Controls
                if ($failed) { $ui.StatusText.Text = "$operation failed. See Activity for details." }
                else { $ui.StatusText.Text = "$operation completed." }
            }
        }
    } finally { $script:inTick = $false }
})
$window.Add_Closing({
    param($sender,$e)
    if ($script:job) {
        $e.Cancel = $true
        Notice 'Wait for the operation to finish. If sign-in is open, complete or cancel it in the Microsoft window.' 'Operation in progress'
    }
})
Log "Ready. WPF v2.0. Log: $script:logFile"
$timer.Start()
try { [void]$window.ShowDialog() }
finally {
    $timer.Stop()
    $cleanup = [PowerShell]::Create(); $cleanup.Runspace = $script:runspace
    try {
        [void]$cleanup.AddScript('if (Get-Command Get-MgContext -ErrorAction SilentlyContinue) { if (Get-MgContext) { Disconnect-MgGraph | Out-Null } }')
        $cleanup.Invoke() | Out-Null
    } catch {} finally { $cleanup.Dispose() }
    $script:runspace.Dispose()
}
