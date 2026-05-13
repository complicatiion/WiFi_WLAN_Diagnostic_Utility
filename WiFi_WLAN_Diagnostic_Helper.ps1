param(
    [ValidateSet('QuickOverview','Adapters','Interfaces','Networks','Profiles','Events','Tests','WlanReport','ExportProfiles','ListXml','ShowXml','FullReport')]
    [string]$Action = 'QuickOverview',
    [string]$XmlPath
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 60)
    Write-Host $Title
    Write-Host ('=' * 60)
}

function Get-ReportRoot {
    $root = Join-Path $env:USERPROFILE 'Desktop\WiFiReports'
    if (-not (Test-Path $root)) {
        New-Item -Path $root -ItemType Directory -Force | Out-Null
    }
    return $root
}

function Get-Timestamp {
    Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
}

function Invoke-NetshText {
    param([string[]]$Arguments)
    try {
        return ((& netsh.exe @Arguments 2>&1 | Out-String).Trim())
    } catch {
        return "Failed to run: netsh $($Arguments -join ' ')"
    }
}

function Get-WlanProfilesText { Invoke-NetshText -Arguments @('wlan','show','profiles') }
function Get-WlanInterfaceText { Invoke-NetshText -Arguments @('wlan','show','interfaces') }
function Get-WlanDriversText { Invoke-NetshText -Arguments @('wlan','show','drivers') }
function Get-WlanNetworksText { Invoke-NetshText -Arguments @('wlan','show','networks','mode=bssid') }

function Get-SystemOverviewObject {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue

    $operatingSys = ''
    $model = ''
    $manufacturer = ''

    if ($os) { $operatingSys = "$($os.Caption) $($os.Version) Build $($os.BuildNumber)" }
    if ($cs) {
        $model = $cs.Model
        $manufacturer = $cs.Manufacturer
    }

    return [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        UserName     = $env:USERNAME
        OperatingSys = $operatingSys
        Model        = $model
        Manufacturer = $manufacturer
    }
}

function Get-CurrentWifiAlias {
    $text = Get-WlanInterfaceText
    $m = [regex]::Match($text, '(?im)^\s*Name\s*:\s*(.+?)\s*$')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }

    try {
        $adapter = Get-NetAdapter -Physical | Where-Object {
            $_.Status -eq 'Up' -and ($_.Name -match 'wi-?fi|wlan|wireless' -or $_.InterfaceDescription -match 'wi-?fi|wlan|wireless|802\.11')
        } | Select-Object -First 1
        if ($adapter) { return $adapter.Name }
    } catch {}

    return $null
}

function Get-WirelessAdapters {
    $rows = @()

    try {
        $netAdapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue
        foreach ($a in $netAdapters) {
            if ($a.Name -match 'wi-?fi|wlan|wireless' -or $a.InterfaceDescription -match 'wi-?fi|wlan|wireless|802\.11') {
                $rows += [pscustomobject]@{
                    Name                 = $a.Name
                    InterfaceDescription = $a.InterfaceDescription
                    Status               = $a.Status
                    MacAddress           = $a.MacAddress
                    LinkSpeed            = $a.LinkSpeed
                    DriverInfo           = ''
                    Source               = 'Get-NetAdapter'
                }
            }
        }
    } catch {}

    try {
        $cim = Get-CimInstance Win32_NetworkAdapter -ErrorAction SilentlyContinue
        foreach ($c in $cim) {
            if ($c.Name -match 'wi-?fi|wlan|wireless|802\.11' -or $c.NetConnectionID -match 'wi-?fi|wlan|wireless' -or $c.Description -match 'wi-?fi|wlan|wireless|802\.11') {
                $exists = $rows | Where-Object {
                    $_.Name -eq $c.NetConnectionID -or $_.InterfaceDescription -eq $c.Name -or $_.InterfaceDescription -eq $c.Description
                } | Select-Object -First 1
                if (-not $exists) {
                    $desc = $c.Name
                    if ($c.Description) { $desc = $c.Description }
                    $rows += [pscustomobject]@{
                        Name                 = $c.NetConnectionID
                        InterfaceDescription = $desc
                        Status               = $c.NetConnectionStatus
                        MacAddress           = $c.MACAddress
                        LinkSpeed            = ''
                        DriverInfo           = ''
                        Source               = 'Win32_NetworkAdapter'
                    }
                }
            }
        }
    } catch {}

    if (-not $rows) {
        return @([pscustomobject]@{
            Name                 = ''
            InterfaceDescription = 'No wireless adapter detected'
            Status               = ''
            MacAddress           = ''
            LinkSpeed            = ''
            DriverInfo           = ''
            Source               = ''
        })
    }

    return ($rows | Sort-Object InterfaceDescription -Unique)
}

function Get-WlanEventRows {
    $logName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'
    $start = (Get-Date).AddDays(-14)
    $events = Get-WinEvent -FilterHashtable @{ LogName = $logName; StartTime = $start } -ErrorAction SilentlyContinue

    $rows = foreach ($ev in $events) {
        $xml = $null
        $dataMap = @{}
        try { $xml = [xml]$ev.ToXml() } catch {}
        if ($xml -and $xml.Event -and $xml.Event.EventData -and $xml.Event.EventData.Data) {
            foreach ($d in $xml.Event.EventData.Data) {
                $name = [string]$d.Name
                $value = [string]$d.'#text'
                if (-not [string]::IsNullOrWhiteSpace($name) -and -not $dataMap.ContainsKey($name)) {
                    $dataMap[$name] = $value
                }
            }
        }

        $msg = ''
        try { $msg = [string]$ev.Message } catch { $msg = '' }

        $ssid = $null
        foreach ($k in $dataMap.Keys) {
            if ($k -match 'ssid|profile') {
                if (-not [string]::IsNullOrWhiteSpace($dataMap[$k])) {
                    $ssid = $dataMap[$k]
                    break
                }
            }
        }
        if (-not $ssid -and $msg) {
            $m1 = [regex]::Match($msg, '(?im)^\s*(Profile Name|Profilname|SSID)\s*:\s*(.+?)\s*$')
            if ($m1.Success) { $ssid = $m1.Groups[2].Value.Trim() }
        }
        if (-not $ssid) { $ssid = 'Unknown / not parsed' }

        $reason = ''
        foreach ($k in $dataMap.Keys) {
            if ($k -match 'reason|failure|status|error') {
                if (-not [string]::IsNullOrWhiteSpace($dataMap[$k])) {
                    $reason = $dataMap[$k]
                    break
                }
            }
        }
        if (-not $reason -and $msg) {
            $single = ($msg -replace '\r?\n', ' ').Trim()
            if ($single.Length -gt 220) { $single = $single.Substring(0,220) + ' ...' }
            $reason = $single
        }

        $type = 'Other'
        $msgLower = ($msg | Out-String).ToLowerInvariant()
        if ($msgLower -match 'disconnect|getrennt|roam|abgebrochen|lost|not available') {
            $type = 'Disconnect / roam'
        } elseif ($msgLower -match 'fail|error|reason|timeout|auth|eap|rejected|association') {
            $type = 'Failure'
        } elseif ($msgLower -match 'connect|connected|verbunden|success') {
            $type = 'Connect'
        }

        [pscustomobject]@{
            TimeCreated = $ev.TimeCreated
            Id          = $ev.Id
            Level       = $ev.LevelDisplayName
            SSID        = $ssid
            Type        = $type
            Reason      = $reason
        }
    }

    return $rows
}

function Get-ProfileNames {
    $txt = Get-WlanProfilesText
    $profileNames = @()
    if ($txt) {
        $txt -split "`r?`n" | ForEach-Object {
            if ($_ -match ':\s*(.+)$' -and $_ -match 'All User Profile|Alle Benutzerprofile|User Profile|Benutzerprofil') {
                $profileNames += $matches[1].Trim()
            }
        }
    }
    return ($profileNames | Sort-Object -Unique)
}

function Show-QuickOverview {
    Write-Section 'System and WiFi overview'
    Get-SystemOverviewObject | Format-List

    Write-Section 'Installed wireless adapters'
    Get-WirelessAdapters | Format-Table -AutoSize

    Write-Section 'Current WiFi interface details'
    $ifText = Get-WlanInterfaceText
    if ([string]::IsNullOrWhiteSpace($ifText)) {
        Write-Host 'No WiFi interface details available.'
    } else {
        Write-Host $ifText
    }

    Write-Section 'Driver summary'
    $drv = Get-WlanDriversText
    if ([string]::IsNullOrWhiteSpace($drv)) {
        Write-Host 'No WLAN driver details available.'
    } else {
        Write-Host $drv
    }

    Write-Section 'Saved profile summary'
    $profiles = Get-WlanProfilesText
    if ([string]::IsNullOrWhiteSpace($profiles)) {
        Write-Host 'No WLAN profiles found.'
    } else {
        Write-Host $profiles
    }
}

function Show-Adapters {
    Write-Section 'Installed wireless adapters'
    Get-WirelessAdapters | Format-Table -AutoSize

    Write-Section 'Raw WLAN driver information'
    $drv = Get-WlanDriversText
    if ($drv) { Write-Host $drv } else { Write-Host 'No WLAN driver information returned.' }
}

function Show-Interfaces {
    Write-Section 'Current WiFi interface details'
    $ifText = Get-WlanInterfaceText
    if ($ifText) { Write-Host $ifText } else { Write-Host 'No active WiFi interface data returned.' }

    $alias = Get-CurrentWifiAlias
    if ($alias) {
        Write-Section ("Current IP configuration for interface: " + $alias)
        try {
            Get-NetIPConfiguration -InterfaceAlias $alias | Format-List
        } catch {
            Write-Host 'IP configuration could not be read.'
        }

        Write-Section ("Current adapter statistics for interface: " + $alias)
        try {
            Get-NetAdapterStatistics -Name $alias | Format-List
        } catch {
            Write-Host 'Adapter statistics are not available.'
        }
    }
}

function Show-Networks {
    Write-Section 'Available WiFi networks (scan)'
    $txt = Get-WlanNetworksText
    if ($txt) { Write-Host $txt } else { Write-Host 'No network scan output returned.' }
}

function Show-Profiles {
    Write-Section 'Saved WLAN profiles'
    $txt = Get-WlanProfilesText
    if ($txt) { Write-Host $txt } else { Write-Host 'No saved profiles found.' }

    $profileNames = Get-ProfileNames
    if ($profileNames) {
        foreach ($p in $profileNames) {
            Write-Section ("Profile details: " + $p)
            $detail = Invoke-NetshText -Arguments @('wlan','show','profile',("name=$p"))
            if ($detail) { Write-Host $detail } else { Write-Host 'No details returned.' }
        }
    }
}

function Show-Events {
    Write-Section 'WLAN AutoConfig log analysis (last 14 days)'
    $rows = Get-WlanEventRows
    if (-not $rows) {
        Write-Host 'No WLAN AutoConfig operational events found in the last 14 days.'
        return
    }

    Write-Section 'Per-SSID event statistics'
    $stats = $rows | Group-Object SSID | ForEach-Object {
        $items = $_.Group
        [pscustomobject]@{
            SSID             = $_.Name
            ConnectEvents    = ($items | Where-Object { $_.Type -eq 'Connect' }).Count
            DisconnectEvents = ($items | Where-Object { $_.Type -eq 'Disconnect / roam' }).Count
            FailureEvents    = ($items | Where-Object { $_.Type -eq 'Failure' }).Count
            OtherEvents      = ($items | Where-Object { $_.Type -eq 'Other' }).Count
            FirstSeen        = ($items | Sort-Object TimeCreated | Select-Object -First 1 -ExpandProperty TimeCreated)
            LastSeen         = ($items | Sort-Object TimeCreated | Select-Object -Last 1 -ExpandProperty TimeCreated)
        }
    } | Sort-Object FailureEvents, DisconnectEvents -Descending
    $stats | Format-Table -AutoSize

    Write-Section 'Recent problematic events'
    $rows | Where-Object { $_.Type -in @('Failure','Disconnect / roam') } |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 40 TimeCreated,Id,SSID,Type,Reason |
        Format-Table -Wrap -AutoSize

    Write-Section 'Interpretation note'
    Write-Host 'Historical latency cannot be reconstructed precisely from native Windows WiFi logs.'
    Write-Host 'This section therefore estimates problem hotspots by SSID using disconnect, roam and failure events.'
    Write-Host 'Use the live latency test section for current connection quality.'
}

function Invoke-PingStats {
    param(
        [Parameter(Mandatory=$true)][string]$Target,
        [int]$Count = 12
    )

    $samples = @()
    try {
        $reply = Test-Connection -ComputerName $Target -Count $Count -ErrorAction SilentlyContinue
        if ($reply) {
            $samples = $reply | Select-Object -ExpandProperty ResponseTime
        }
    } catch {}

    if (-not $samples) {
        return [pscustomobject]@{
            Target        = $Target
            Sent          = $Count
            Received      = 0
            PacketLossPct = 100
            MinMs         = ''
            AvgMs         = ''
            MaxMs         = ''
            JitterMs      = ''
        }
    }

    $avg = [math]::Round((($samples | Measure-Object -Average).Average),2)
    $min = [math]::Round((($samples | Measure-Object -Minimum).Minimum),2)
    $max = [math]::Round((($samples | Measure-Object -Maximum).Maximum),2)

    if ($samples.Count -gt 1) {
        $diffs = for ($i=1; $i -lt $samples.Count; $i++) { [math]::Abs($samples[$i] - $samples[$i-1]) }
        $jitter = [math]::Round((($diffs | Measure-Object -Average).Average),2)
    } else {
        $jitter = 0
    }

    return [pscustomobject]@{
        Target        = $Target
        Sent          = $Count
        Received      = $samples.Count
        PacketLossPct = [math]::Round((($Count - $samples.Count) / $Count) * 100,2)
        MinMs         = $min
        AvgMs         = $avg
        MaxMs         = $max
        JitterMs      = $jitter
    }
}

function Show-Tests {
    Write-Section 'Current WiFi connection'
    $ifText = Get-WlanInterfaceText
    if ($ifText) { Write-Host $ifText } else { Write-Host 'No current WiFi interface data returned.' }

    $alias = Get-CurrentWifiAlias
    $targets = New-Object System.Collections.ArrayList

    if ($alias) {
        Write-Section ("Resolved network path for interface: " + $alias)
        try {
            $cfg = Get-NetIPConfiguration -InterfaceAlias $alias
            $gateway = $null
            $dns = $null
            $ip = $null

            if ($cfg.IPv4DefaultGateway) { $gateway = $cfg.IPv4DefaultGateway.NextHop }
            if ($cfg.DNSServer -and $cfg.DNSServer.ServerAddresses) { $dns = ($cfg.DNSServer.ServerAddresses | Select-Object -First 1) }
            if ($cfg.IPv4Address) { $ip = ($cfg.IPv4Address | Select-Object -ExpandProperty IPAddress) -join ', ' }

            [pscustomobject]@{
                InterfaceAlias = $alias
                IPv4Address    = $ip
                Gateway        = $gateway
                DnsServer      = $dns
            } | Format-List

            if ($gateway) { [void]$targets.Add($gateway) }
            if ($dns) { [void]$targets.Add($dns) }
        } catch {
            Write-Host 'Could not resolve IP configuration for the current WiFi interface.'
        }
    }

    [void]$targets.Add('1.1.1.1')
    [void]$targets.Add('8.8.8.8')
    $targets = $targets | Select-Object -Unique

    Write-Section 'Latency and packet-loss tests'
    $results = foreach ($t in $targets) { Invoke-PingStats -Target $t -Count 12 }
    $results | Format-Table -AutoSize

    Write-Section 'Simple interpretation'
    $assessmentRows = foreach ($r in $results) {
        $avgValue = 0
        if ($r.AvgMs -ne '') { $avgValue = [double]$r.AvgMs }

        if ($r.PacketLossPct -ge 10 -or $avgValue -ge 120) {
            $state = 'Problematic'
        } elseif ($r.PacketLossPct -gt 0 -or $avgValue -ge 60) {
            $state = 'Warning'
        } else {
            $state = 'Good'
        }

        [pscustomobject]@{
            Target        = $r.Target
            PacketLossPct = $r.PacketLossPct
            AvgMs         = $r.AvgMs
            JitterMs      = $r.JitterMs
            Assessment    = $state
        }
    }
    $assessmentRows | Format-Table -AutoSize
}

function Show-WlanReport {
    Write-Section 'Generating Windows WLAN report'
    $raw = Invoke-NetshText -Arguments @('wlan','show','wlanreport')
    if ($raw) { Write-Host $raw }

    $defaultPath = Join-Path $env:ProgramData 'Microsoft\Windows\WlanReport\wlan-report-latest.html'
    if (Test-Path $defaultPath) {
        Write-Host ''
        Write-Host 'WLAN report found at:'
        Write-Host $defaultPath
        Start-Process $defaultPath | Out-Null
    } else {
        Write-Host ''
        Write-Host 'The report command completed, but the expected HTML file was not found at the default path.'
    }
}

function Export-WlanProfiles {
    $root = Get-ReportRoot
    $dest = Join-Path $root ("WLAN_Profile_XML_" + (Get-Timestamp))
    New-Item -Path $dest -ItemType Directory -Force | Out-Null

    Write-Section 'Exporting WLAN profiles to XML'
    $raw = Invoke-NetshText -Arguments @('wlan','export','profile',("folder=$dest"))
    if ($raw) { Write-Host $raw }

    if (Test-Path $dest) {
        Write-Host ''
        Write-Host 'Export folder:'
        Write-Host $dest
        Start-Process explorer.exe -ArgumentList $dest | Out-Null
    }
}

function List-XmlFiles {
    Write-Section 'Native Windows WLAN XML folder'
    $native = Join-Path $env:ProgramData 'Microsoft\Wlansvc\Profiles\Interfaces'
    if (Test-Path $native) {
        Get-ChildItem -Path $native -Filter *.xml -Recurse -ErrorAction SilentlyContinue |
            Select-Object FullName,Length,LastWriteTime |
            Format-Table -AutoSize
    } else {
        Write-Host 'Native Windows WLAN XML folder was not found.'
    }

    Write-Section 'Exported XML files in report folder'
    $root = Get-ReportRoot
    $files = Get-ChildItem -Path $root -Filter *.xml -Recurse -ErrorAction SilentlyContinue
    if ($files) {
        $files | Select-Object FullName,Length,LastWriteTime | Format-Table -AutoSize
    } else {
        Write-Host 'No exported XML files found in the report folder.'
    }
}

function Show-XmlFile {
    param([string]$Path)
    Write-Section 'XML file content'
    if (-not $Path) {
        Write-Host 'No XML path was provided.'
        return
    }
    if (-not (Test-Path $Path)) {
        Write-Host 'The specified XML file was not found.'
        Write-Host $Path
        return
    }
    try {
        Get-Content -Path $Path -TotalCount 400
    } catch {
        Write-Host 'Failed to read the XML file.'
        Write-Host $Path
    }
}

function Get-EventStatisticsText {
    $eventRows = Get-WlanEventRows
    if (-not $eventRows) {
        return "No WLAN AutoConfig operational events found in the last 14 days.`r`n"
    }

    $text = ""
    $stats = $eventRows | Group-Object SSID | ForEach-Object {
        $items = $_.Group
        [pscustomobject]@{
            SSID             = $_.Name
            ConnectEvents    = ($items | Where-Object { $_.Type -eq 'Connect' }).Count
            DisconnectEvents = ($items | Where-Object { $_.Type -eq 'Disconnect / roam' }).Count
            FailureEvents    = ($items | Where-Object { $_.Type -eq 'Failure' }).Count
            OtherEvents      = ($items | Where-Object { $_.Type -eq 'Other' }).Count
            FirstSeen        = ($items | Sort-Object TimeCreated | Select-Object -First 1 -ExpandProperty TimeCreated)
            LastSeen         = ($items | Sort-Object TimeCreated | Select-Object -Last 1 -ExpandProperty TimeCreated)
        }
    } | Sort-Object FailureEvents, DisconnectEvents -Descending

    $text += ($stats | Format-Table -AutoSize | Out-String)
    $text += "`r`nRecent problematic WLAN events`r`n"
    $text += (($eventRows | Where-Object { $_.Type -in @('Failure','Disconnect / roam') } |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 40 TimeCreated,Id,SSID,Type,Reason |
        Format-Table -Wrap -AutoSize | Out-String))
    return $text
}

function Write-FullReport {
    $root = Get-ReportRoot
    $stamp = Get-Timestamp
    $folder = Join-Path $root ("WiFi_Audit_" + $stamp)
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
    $report = Join-Path $folder ("WiFi_WLAN_Diagnostic_Report_" + $stamp + '.txt')

    $wlanReportPath = Join-Path $env:ProgramData 'Microsoft\Windows\WlanReport\wlan-report-latest.html'
    Invoke-NetshText -Arguments @('wlan','show','wlanreport') | Out-Null
    Invoke-NetshText -Arguments @('wlan','export','profile',("folder=$folder")) | Out-Null

    @"
============================================================
WiFi / WLAN Diagnostic Report
============================================================
Date: $(Get-Date)
Computer: $env:COMPUTERNAME
User: $env:USERNAME
ReportFolder: $folder
"@ | Set-Content -Path $report -Encoding UTF8

    Add-Content -Path $report -Value "`r`n[1] Quick overview`r`n"
    (Get-SystemOverviewObject | Format-List | Out-String) | Add-Content -Path $report

    Add-Content -Path $report -Value "`r`n[2] Installed wireless adapters`r`n"
    (Get-WirelessAdapters | Format-Table -AutoSize | Out-String) | Add-Content -Path $report

    Add-Content -Path $report -Value "`r`n[3] Current WiFi interface details`r`n"
    (Get-WlanInterfaceText | Out-String) | Add-Content -Path $report

    Add-Content -Path $report -Value "`r`n[4] WLAN driver details`r`n"
    (Get-WlanDriversText | Out-String) | Add-Content -Path $report

    Add-Content -Path $report -Value "`r`n[5] Available networks scan`r`n"
    (Get-WlanNetworksText | Out-String) | Add-Content -Path $report

    Add-Content -Path $report -Value "`r`n[6] Saved WLAN profiles`r`n"
    (Get-WlanProfilesText | Out-String) | Add-Content -Path $report

    Add-Content -Path $report -Value "`r`n[7] Event-based SSID statistics`r`n"
    (Get-EventStatisticsText) | Add-Content -Path $report

    Add-Content -Path $report -Value "`r`n[8] Connectivity and latency tests`r`n"
    $alias = Get-CurrentWifiAlias
    $targets = New-Object System.Collections.ArrayList
    if ($alias) {
        try {
            $cfg = Get-NetIPConfiguration -InterfaceAlias $alias
            if ($cfg.IPv4DefaultGateway) { [void]$targets.Add($cfg.IPv4DefaultGateway.NextHop) }
            if ($cfg.DNSServer -and $cfg.DNSServer.ServerAddresses) { [void]$targets.Add(($cfg.DNSServer.ServerAddresses | Select-Object -First 1)) }
        } catch {}
    }
    [void]$targets.Add('1.1.1.1')
    [void]$targets.Add('8.8.8.8')
    $targets = $targets | Select-Object -Unique
    ($targets | ForEach-Object { Invoke-PingStats -Target $_ -Count 12 } | Format-Table -AutoSize | Out-String) | Add-Content -Path $report

    Add-Content -Path $report -Value "`r`n[9] Native WLAN XML location`r`n"
    $native = Join-Path $env:ProgramData 'Microsoft\Wlansvc\Profiles\Interfaces'
    if (Test-Path $native) {
        Add-Content -Path $report -Value ($native + "`r`n")
        (Get-ChildItem -Path $native -Filter *.xml -Recurse -ErrorAction SilentlyContinue |
            Select-Object FullName,Length,LastWriteTime |
            Format-Table -AutoSize | Out-String) | Add-Content -Path $report
    } else {
        Add-Content -Path $report -Value "Native WLAN XML folder not found.`r`n"
    }

    Add-Content -Path $report -Value "`r`n[10] Generated Windows WLAN report`r`n"
    if (Test-Path $wlanReportPath) {
        Add-Content -Path $report -Value ($wlanReportPath + "`r`n")
    } else {
        Add-Content -Path $report -Value "The default WLAN HTML report path was not found.`r`n"
    }

    Write-Host 'Report created:'
    Write-Host $report
    Write-Host ''
    Write-Host 'Artifacts in folder:'
    Write-Host $folder
    Start-Process explorer.exe -ArgumentList $folder | Out-Null
}

try {
    switch ($Action) {
        'QuickOverview'  { Show-QuickOverview }
        'Adapters'       { Show-Adapters }
        'Interfaces'     { Show-Interfaces }
        'Networks'       { Show-Networks }
        'Profiles'       { Show-Profiles }
        'Events'         { Show-Events }
        'Tests'          { Show-Tests }
        'WlanReport'     { Show-WlanReport }
        'ExportProfiles' { Export-WlanProfiles }
        'ListXml'        { List-XmlFiles }
        'ShowXml'        { Show-XmlFile -Path $XmlPath }
        'FullReport'     { Write-FullReport }
        default          { Show-QuickOverview }
    }
    exit 0
} catch {
    Write-Host ''
    Write-Host 'The helper encountered an unexpected error:'
    Write-Host $_.Exception.Message
    exit 1
}
