@echo off
setlocal
cd /d "%~dp0"
set "Q2_VIVADO=C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat"
if defined Q2_VIVADO_BIN set "Q2_VIVADO=%Q2_VIVADO_BIN%\vivado.bat"
if exist "%Q2_VIVADO%" goto run
for /f "delims=" %%V in ('where vivado.bat 2^>nul') do set "Q2_VIVADO=%%V"
if exist "%Q2_VIVADO%" goto run
echo Vivado was not found. Set Q2_VIVADO_BIN to the Vivado bin directory.
pause
exit /b 1
:run
call "%Q2_VIVADO%" -mode batch -source "%~dp0run_implementation.tcl"
if errorlevel 1 goto failed
echo ALL 3 DEFECT-AWARE COMPARISON IMPLEMENTATIONS COMPLETED
pause
exit /b 0
:failed
echo Run failed. Send vivado.log and the latest RUN_FAILED.txt or FAILED.txt.
pause
exit /b 1
