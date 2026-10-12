@echo off
setlocal
cd /d "%~dp0"
if not exist review_results (
  echo ERROR: review_results does not exist. Run the experiments first.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path 'review_results\*' -DestinationPath 'q2_review_results.zip' -Force"
if errorlevel 1 exit /b 1
echo PASS: created %CD%\q2_review_results.zip
echo Send that ZIP back for paper-table and figure integration.
endlocal

