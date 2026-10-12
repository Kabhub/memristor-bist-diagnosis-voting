@echo off
setlocal
cd /d "%~dp0"
where vivado >nul 2>nul
if errorlevel 1 (
  echo ERROR: Vivado was not found on PATH.
  echo Open the Vivado Tcl Shell and follow RUN_FROM_VIVADO_TCL.txt instead.
  exit /b 1
)
vivado -mode batch -notrace -source tcl\run_review_functional_sim.tcl
if errorlevel 1 exit /b 1
echo PASS: reviewer functional simulations completed.
endlocal

