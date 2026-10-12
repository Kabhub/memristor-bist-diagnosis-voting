@echo off
setlocal
cd /d "%~dp0"
py -3 python\summarize_registered_results.py review_results\vivado_quick_registered_v7\implementation_summary.csv --output review_results\vivado_quick_registered_v7
if errorlevel 1 exit /b 1
echo Registered benchmark summaries completed.
endlocal
