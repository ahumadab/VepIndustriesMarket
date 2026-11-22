@echo off
rem Installs the Sync script (Sync.ps1): asks the invitation code once, then creates its scheduled task, no admin.
rem Extra arguments go to Sync.ps1, e.g. installer.cmd -Api https://api-staging.vepindustries.com
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync.ps1" -Install %*
pause
