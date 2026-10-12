@echo off
setlocal
cd /d "%~dp0"
where vivado >nul 2>nul
if errorlevel 1 (
  echo ERROR: Vivado was not found on PATH. Use the Tcl Console command in START_HERE_OOC_V5.txt.
  exit /b 1
)
call vivado -mode batch -notrace -log review_smoke_v6.log -journal review_smoke_v6.jou -source tcl\run_vivado_smoke.tcl
if errorlevel 1 (
  echo ERROR: smoke run failed. Send review_smoke_v5.log and the new FAILED.txt.
  exit /b 1
)
echo Smoke run returned. Send the new CSV and timing report before continuing.
endlocal
