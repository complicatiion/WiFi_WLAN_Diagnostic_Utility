# WiFi / WLAN Diagnostic Utility

A batch-driven Windows diagnostic utility for Wi-Fi / WLAN troubleshooting on Windows 11 systems.

The script uses a batch menu as the front end and PowerShell in the background for the more advanced checks. It is designed to stay robust and readable instead of trying to do overly fragile deep parsing.

## Purpose

This utility helps analyze:

- installed Wi-Fi / WLAN cards and adapter details
- current SSID and active connection details
- visible wireless networks in range
- saved WLAN profiles
- disconnects, failures, and other WLAN AutoConfig events
- live latency and packet-loss tests
- Windows WLAN reports
- native and exported Windows Wi-Fi XML profile files

It is especially useful when you want a quick troubleshooting audit on a Windows 11 PC without manually running many individual commands.

## Main Features

### 1. Quick WiFi overview
Shows a compact overview of:

- system information
- detected wireless adapters
- current Wi-Fi interface details
- WLAN driver information
- saved WLAN profile summary

### 2. Installed WiFi cards / adapters
Checks which wireless cards are present and displays:

- adapter name
- interface description
- status
- MAC address
- link speed where available

It also includes raw `netsh wlan show drivers` output.

### 3. Current WiFi connection details
Shows the current wireless connection information including the active interface and the raw output from:

```text
netsh wlan show interfaces
```

If possible, it also shows the current IP configuration and adapter statistics for the active Wi-Fi interface.

### 4. Available WiFi networks scan
Runs:

```text
netsh wlan show networks mode=bssid
```

This helps inspect:

- visible SSIDs
- BSSIDs
- channel information
- signal quality
- authentication and encryption information

### 5. Saved WLAN profiles
Lists saved Windows WLAN profiles and attempts to show details for each profile.

### 6. Event-based issue analysis and per-SSID statistics
Analyzes the Windows WLAN AutoConfig operational log for the last 14 days and builds a practical issue summary by SSID.

The script groups events into categories such as:

- Connect
- Disconnect / roam
- Failure
- Other

This gives a useful estimate of which SSID had the most disconnects or failures.

Important note: Windows event logs do **not** provide precise historical end-to-end latency statistics per SSID.  
For that reason, the script estimates problem hotspots based on disconnect, roam, and failure events, and combines this with live latency tests for the currently active connection.

### 7. Connectivity and latency tests
Runs live packet-loss and latency tests against:

- the current default gateway, if available
- the current DNS server, if available
- `1.1.1.1`
- `8.8.8.8`

The script outputs:

- sent / received counts
- packet loss percentage
- minimum latency
- average latency
- maximum latency
- rough jitter estimate

### 8. Windows WLAN report
Runs:

```text
netsh wlan show wlanreport
```

This generates the built-in Windows wireless HTML report and opens it.

### 9. Native Windows WLAN XML folder
Opens the native Windows Wi-Fi profile folder:

```text
%ProgramData%\Microsoft\Wlansvc\Profiles\Interfaces
```

This is useful if you want to inspect the underlying profile XML files directly.

### 10. Export WLAN profiles to XML
Exports Windows WLAN profiles into a report folder on the desktop.

By design, the script exports profiles **without forcing clear-text key export**.  
That keeps the default behavior safer while still making the XML structure available for review and editing.

### 11. XML listing and inspection
The utility can:

- list native XML files
- list exported XML files
- display XML file contents in the console
- open a chosen XML file in Notepad

## Report Output

The utility can create a full report under:

```text
%USERPROFILE%\Desktop\WiFiReports
```

A full report includes:

- adapter overview
- interface details
- driver output
- visible network scan
- saved profile summary
- per-SSID event statistics
- recent problem events
- live latency tests
- native XML folder inventory
- exported XML files
- Windows WLAN report reference

## Requirements

- Windows 11
- PowerShell available
- administrative rights recommended
- WLAN AutoConfig logging available for historical analysis
- a Wi-Fi capable device / driver installed

## Design Notes

The script intentionally prefers robust checks over overly aggressive parsing.

This means:

- raw `netsh` output is shown where that is more reliable
- event statistics are derived conservatively
- historical latency is estimated indirectly through disconnect and failure events
- XML editing is handled through folder access, export, display, and Notepad opening

## Useful Built-In Commands Behind the Script

The utility relies heavily on standard Windows WLAN diagnostics such as:

```text
netsh wlan show drivers
netsh wlan show interfaces
netsh wlan show networks mode=bssid
netsh wlan show profiles
netsh wlan show wlanreport
netsh wlan export profile
```

## Disclaimer

This utility is intended for diagnostic and administrative troubleshooting use.

It should be tested in your own environment before broad operational use, especially if you plan to inspect or modify native WLAN XML profile files.


---

### complicatiion aka sksdesign 13.05.2026

---

