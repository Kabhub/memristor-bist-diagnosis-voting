@echo off
setlocal
cd /d "%~dp0"
if not exist review_results\vivado_quick_ooc_v6\implementation_summary.csv (
  echo ERROR: implementation_summary.csv was not found.
  echo Run the quick Vivado campaign first.
  exit /b 1
)
py -3 python\summarize_vivado_results.py review_results\vivado_quick_ooc_v6\implementation_summary.csv --output review_results\vivado_quick_ooc_v6
if errorlevel 1 exit /b 1
echo PASS: Vivado summary tables and 300-dpi/vector figures created.
endlocal

