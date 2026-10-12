@echo off
setlocal
cd /d "%~dp0"
where vivado >nul 2>nul
if errorlevel 1 (
  echo ERROR: Vivado is not on PATH. Use the Tcl Console.
  exit /b 1
)
call vivado -mode batch -notrace -log review_registered_quick_v7.log -journal review_registered_quick_v7.jou -source tcl\run_vivado_registered_quick.tcl
if errorlevel 1 exit /b 1
echo Campaign completed. Timing violations, if any, remain recorded in the CSV.
endlocal
