@echo off
setlocal

rem ============================================================
rem WSL SAFE LAUNCHER
rem - Find PowerShell script in same directory
rem - Parse-check PowerShell syntax BEFORE execution
rem - Never execute the PS1 if syntax validation fails
rem - Keep window open so errors can be read
rem ============================================================

cd /d "%~dp0"

set "SCRIPT=%~dp0wsl-safe-backup-restore.ps1"

echo ========================================
echo  WSL SAFE LAUNCHER - SYNTAX CHECK
echo ========================================
echo.
echo Script:
echo   %SCRIPT%
echo.

rem ============================================================
rem CHECK SCRIPT EXISTS
rem ============================================================

if not exist "%SCRIPT%" (
    echo [ERROR] Script not found:
    echo   %SCRIPT%
    echo.
    pause
    exit /b 1
)

rem ============================================================
rem POWERSHELL SYNTAX CHECK
rem
rem IMPORTANT:
rem Do NOT use PowerShell pipelines here.
rem This avoids CMD escaping problems with ^ and ^|
rem ============================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
"$ErrorList=$null; $TokenList=$null; [System.Management.Automation.Language.Parser]::ParseFile($env:SCRIPT,[ref]$TokenList,[ref]$ErrorList) > $null; if($ErrorList.Count -gt 0){ Write-Host ''; Write-Host '========================================' -ForegroundColor Red; Write-Host ' POWERSHELL SYNTAX ERROR' -ForegroundColor Red; Write-Host '========================================' -ForegroundColor Red; Write-Host ''; foreach($Item in $ErrorList){ Write-Host ('Line {0}, Col {1}: {2}' -f $Item.Extent.StartLineNumber,$Item.Extent.StartColumnNumber,$Item.Message) -ForegroundColor Red }; exit 2 } else { Write-Host '[OK] PowerShell syntax check passed.' -ForegroundColor Green; exit 0 }"

set "CHECK_RC=%ERRORLEVEL%"

rem ============================================================
rem STOP IF SYNTAX CHECK FAILED
rem ============================================================

if not "%CHECK_RC%"=="0" (
    echo.
    echo ========================================
    echo  SCRIPT NOT EXECUTED
    echo ========================================
    echo.
    echo PowerShell syntax validation failed.
    echo No WSL operation was started.
    echo.
    echo Exit code: %CHECK_RC%
    echo.
    pause
    exit /b %CHECK_RC%
)

rem ============================================================
rem RUN SCRIPT
rem ============================================================

echo.
echo ========================================
echo  STARTING WSL SCRIPT
echo ========================================
echo.

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%SCRIPT%"

set "RC=%ERRORLEVEL%"

rem ============================================================
rem FINISHED
rem ============================================================

echo.
echo ========================================
echo  SCRIPT FINISHED - Exit code: %RC%
echo ========================================
echo.

if not "%RC%"=="0" (
    echo [WARNING] The PowerShell script returned an error.
    echo Review the messages above before doing anything else.
    echo.
)

pause

exit /b %RC%