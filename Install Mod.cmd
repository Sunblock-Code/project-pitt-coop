@echo off
setlocal
cd /d "%~dp0"
py -3 --version >nul 2>&1
if not errorlevel 1 (
    py -3 "%~dp0co-op\tools\build.py" %*
    goto result
)
python --version >nul 2>&1
if not errorlevel 1 (
    python "%~dp0co-op\tools\build.py" %*
    goto result
)
echo Python 3 is required to install this mod. Install it from https://www.python.org/downloads/windows/
echo Then run this installer again.
pause
exit /b 1
:result
if errorlevel 1 (
    echo Installation failed. Read the error above.
    pause
    exit /b 1
)
echo Run Play Co-op.cmd to play.
pause
