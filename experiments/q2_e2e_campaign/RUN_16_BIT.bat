@echo off
setlocal
cd /d "%~dp0"
set "Q2_VIVADO=C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat"
if defined Q2_VIVADO_BIN set "Q2_VIVADO=%Q2_VIVADO_BIN%\vivado.bat"
if exist "%Q2_VIVADO%" goto run
for /f "delims=" %%V in ('where vivado.bat 2^>nul') do set "Q2_VIVADO=%%V"
if exist "%Q2_VIVADO%" goto run
echo Vivado was not found. Open an empty Vivado session and run:
echo source {C:/Q2/E2E_BIST/run_e2e.tcl}
pause
exit /b 1
:run
echo Running the 16-bit end-to-end BIST campaign. No synthesis or routing.
call "%Q2_VIVADO%" -mode batch -source "%~dp0run_e2e.tcl" -tclargs 16
if errorlevel 1 goto failed
echo Check the final ALL 4609 END-TO-END BIST SCENARIOS PASSED message.
echo Open LATEST_RUN.txt for the result directory.
pause
exit /b 0
:failed
echo The campaign did not complete. Send the Vivado log and latest RUN_FAILED.txt.
pause
exit /b 1
