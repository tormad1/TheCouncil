@echo off
pushd "%~dp0"
python system\run.py %*
set "councilExit=%ERRORLEVEL%"
popd
exit /b %councilExit%
