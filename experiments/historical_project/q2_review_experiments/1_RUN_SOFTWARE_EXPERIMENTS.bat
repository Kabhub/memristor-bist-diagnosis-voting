@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 (
  echo ERROR: Python launcher "py" was not found. Run 0_INSTALL_PYTHON_DEPS.bat first.
  exit /b 1
)
echo [1/3] Exact 8/16/32-bit fault coverage...
py -3 python\run_fault_coverage.py --output review_results\coverage
if errorlevel 1 exit /b 1
echo [2/3] Calibrated threshold and repeated-read variation study...
py -3 python\run_adaptive_variation.py --output review_results\variation
if errorlevel 1 exit /b 1
echo [3/3] Published VTEAM model validation...
py -3 python\run_vteam_validation.py --output review_results\device_validation
if errorlevel 1 exit /b 1
echo.
echo PASS: all software experiments completed.
echo Next: follow RUN_FROM_VIVADO_TCL.txt.
endlocal

