@echo off
setlocal EnableExtensions

set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell.exe"
set "SCRIPT_DIR=%~dp0"
set "HELPER=%SCRIPT_DIR%WiFi_WLAN_Diagnostic_Helper.ps1"

title WiFi / WLAN Diagnostic Utility
color 0B
chcp 65001 >nul

net session >nul 2>&1
if errorlevel 1 (
  set "ISADMIN=0"
) else (
  set "ISADMIN=1"
)

set "REPORTROOT=%USERPROFILE%\Desktop\WiFiReports"
if not exist "%REPORTROOT%" md "%REPORTROOT%" >nul 2>&1

if not exist "%HELPER%" (
  cls
  echo ============================================================
  echo WiFi / WLAN Diagnostic Utility
  echo 		by complicatiion
  echo ============================================================
  echo.
  echo Helper script not found:
  echo %HELPER%
  echo.
  pause
  goto END
)

:MAIN
cls
echo ============================================================
echo.
echo                 WiFi / WLAN Diagnostic Utility
echo                       by complicatiion
echo ============================================================
echo.
if "%ISADMIN%"=="1" (
  echo Admin Status : YES
) else (
  echo Admin Status : NO
)
echo Report Folder : %REPORTROOT%
echo Helper Script : %HELPER%
echo.
echo [1] Quick WiFi overview
echo [2] Installed WiFi cards / adapters
echo [3] Current WiFi connection details
echo [4] Available WiFi networks scan
echo [5] Saved WLAN profiles
echo [6] Event-based issue analysis and per-SSID statistics
echo [7] Connectivity and latency tests
echo [8] Generate and open Windows WLAN report
echo [9] Open native Windows WLAN XML folder
echo [A] Export WLAN profiles to XML
echo [B] List XML files
echo [C] Show XML content
echo [D] Open XML file in Notepad
echo [E] Create full report
echo [F] Open report folder
echo [0] Exit
echo.
set "CHO="
set /p CHO="Selection: "

if "%CHO%"=="1" goto QUICK
if "%CHO%"=="2" goto ADAPTERS
if "%CHO%"=="3" goto INTERFACES
if "%CHO%"=="4" goto NETWORKS
if "%CHO%"=="5" goto PROFILES
if "%CHO%"=="6" goto EVENTS
if "%CHO%"=="7" goto TESTS
if "%CHO%"=="8" goto WLANREPORT
if "%CHO%"=="9" goto OPENNATIVEXML
if /I "%CHO%"=="A" goto EXPORTXML
if /I "%CHO%"=="B" goto LISTXML
if /I "%CHO%"=="C" goto SHOWXML
if /I "%CHO%"=="D" goto EDITXML
if /I "%CHO%"=="E" goto FULLREPORT
if /I "%CHO%"=="F" goto OPENREPORT
if "%CHO%"=="0" goto END
goto MAIN

:QUICK
cls
echo ============================================================
echo Quick WiFi overview
echo ============================================================
echo.
call :RUNHELPER QuickOverview
goto MAIN

:ADAPTERS
cls
echo ============================================================
echo Installed WiFi cards / adapters
echo ============================================================
echo.
call :RUNHELPER Adapters
goto MAIN

:INTERFACES
cls
echo ============================================================
echo Current WiFi connection details
echo ============================================================
echo.
call :RUNHELPER Interfaces
goto MAIN

:NETWORKS
cls
echo ============================================================
echo Available WiFi networks scan
echo ============================================================
echo.
call :RUNHELPER Networks
goto MAIN

:PROFILES
cls
echo ============================================================
echo Saved WLAN profiles
echo ============================================================
echo.
call :RUNHELPER Profiles
goto MAIN

:EVENTS
cls
echo ============================================================
echo Event-based issue analysis and per-SSID statistics
echo ============================================================
echo.
call :RUNHELPER Events
goto MAIN

:TESTS
cls
echo ============================================================
echo Connectivity and latency tests
echo ============================================================
echo.
call :RUNHELPER Tests
goto MAIN

:WLANREPORT
cls
echo ============================================================
echo Generate and open Windows WLAN report
echo ============================================================
echo.
call :RUNHELPER WlanReport
goto MAIN

:OPENNATIVEXML
cls
echo ============================================================
echo Open native Windows WLAN XML folder
echo ============================================================
echo.
if exist "%ProgramData%\Microsoft\Wlansvc\Profiles\Interfaces" (
  start "" explorer.exe "%ProgramData%\Microsoft\Wlansvc\Profiles\Interfaces"
  echo Opened:
  echo %ProgramData%\Microsoft\Wlansvc\Profiles\Interfaces
) else (
  echo Native WLAN profile folder was not found.
)
echo.
pause
goto MAIN

:EXPORTXML
cls
echo ============================================================
echo Export WLAN profiles to XML
echo ============================================================
echo.
call :RUNHELPER ExportProfiles
goto MAIN

:LISTXML
cls
echo ============================================================
echo List XML files
echo ============================================================
echo.
call :RUNHELPER ListXml
goto MAIN

:SHOWXML
cls
echo ============================================================
echo Show XML content
echo ============================================================
echo.
set "XMLPATH="
set /p XMLPATH="Enter full XML file path: "
if not defined XMLPATH goto MAIN
call :RUNHELPER ShowXml "%XMLPATH%"
goto MAIN

:EDITXML
cls
echo ============================================================
echo Open XML file in Notepad
echo ============================================================
echo.
set "XMLPATH="
set /p XMLPATH="Enter full XML file path: "
if not defined XMLPATH goto MAIN
if exist "%XMLPATH%" (
  start "" notepad.exe "%XMLPATH%"
  echo Opened in Notepad:
  echo %XMLPATH%
) else (
  echo File not found:
  echo %XMLPATH%
)
echo.
pause
goto MAIN

:FULLREPORT
cls
echo ============================================================
echo Create full report
echo ============================================================
echo.
call :RUNHELPER FullReport
goto MAIN

:OPENREPORT
start "" explorer.exe "%REPORTROOT%"
goto MAIN

:RUNHELPER
set "ACTION=%~1"
set "XMLARG=%~2"
if defined XMLARG (
  "%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action "%ACTION%" -XmlPath "%XMLARG%"
) else (
  "%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action "%ACTION%"
)
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo PowerShell helper returned exit code %RC%.
  echo.
)
pause
exit /b 0

:END
endlocal
exit /b 0
