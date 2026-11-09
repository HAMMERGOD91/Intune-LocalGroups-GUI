# Pure naming/search helpers; no Graph calls or GUI dependencies.
function Get-CoeSearchPattern {
    param([string]$Query)
    $parts = @($Query.Trim() -split '[\s*\-]+' | Where-Object { $_ })
    if (($parts -join '').Length -lt 2) { throw 'Enter at least two letters or numbers, for example ece-mg-baas or ece-dg-baas.' }
    # Literal tokens in order; intervening name segments are allowed.
    return (($parts | ForEach-Object { [regex]::Escape($_) }) -join '.*')
}
function Get-CoeGroupInfo {
    param([string]$Name)
    if ($Name -notmatch '^COE-(?<Dept>[^-]+)-(?<Kind>MG|DG)-(?<Details>.+)$') { return $null }
    $dept = $Matches.Dept.ToUpperInvariant(); $kind = $Matches.Kind.ToUpperInvariant()
    $details = $Matches.Details
    $adminGroup = $Name -match '-Admins$'
    if ($adminGroup) { $details = $details -replace '-Admins$','' }
    if (-not $details) { return $null }
    $destinations = @('Users','RDP')
    if ($kind -eq 'DG') { $destinations = @('Devices') }
    elseif ($adminGroup) { $destinations = @('Administrators') }
    [pscustomobject]@{
        PolicyName = "COE-${dept}: Set User Groups ($details)"
        Destinations = $destinations
        Kind = $kind
    }
}
