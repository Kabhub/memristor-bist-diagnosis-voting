@echo off
setlocal
cd /d "%~dp0"
where vivado >nul 2>nul
if errorlevel 1 (
  echo ERROR: Vivado was not found on PATH.
  echo Open the Vivado Tcl Shell and follow RUN_FROM_VIVADO_TCL.txt instead.
  exit /b 1
)
call vivado -mode batch -notrace -log review_quick_v6.log -journal review_quick_v6.jou -source tcl\run_vivado_quick.tcl
if errorlevel 1 exit /b 1
echo PASS: recommended Vivado campaign completed.
echo Next: run 4_SUMMARIZE_VIVADO_QUICK.bat.
endlocal

