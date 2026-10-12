@echo off
setlocal
cd /d "%~dp0"
where vivado >nul 2>nul
if errorlevel 1 (
  echo ERROR: Vivado was not found on PATH. Follow RUN_FROM_VIVADO_TCL.txt.
  exit /b 1
)
echo WARNING: the full campaign is substantially longer than the quick campaign.
vivado -mode batch -notrace -source tcl\run_vivado_full.tcl
if errorlevel 1 exit /b 1
echo PASS: full Vivado campaign completed.
endlocal

