@echo off
setlocal
cd /d "%~dp0"
where vivado >nul 2>nul
if errorlevel 1 (
  echo ERROR: Vivado is not on PATH. Use the Tcl Console command in START_HERE_REGISTERED_V7.txt.
  exit /b 1
)
call vivado -mode batch -notrace -log review_registered_check_v7.log -journal review_registered_check_v7.jou -source tcl\run_vivado_registered_smoke.tcl
if errorlevel 1 exit /b 1
echo Implementation check completed. Inspect timing_met in the CSV; completion is not timing closure.
endlocal
