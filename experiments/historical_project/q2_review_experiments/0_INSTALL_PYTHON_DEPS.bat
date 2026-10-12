@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 (
  echo ERROR: Python launcher "py" was not found.
  echo Install Python 3.10 or newer, enable "Add Python to PATH", then rerun.
  exit /b 1
)
py -3 -m pip install -r requirements.txt
if errorlevel 1 exit /b 1
echo.
echo PASS: Python dependencies are installed.
endlocal

