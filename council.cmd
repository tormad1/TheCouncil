@echo off
pushd "%~dp0"
if /I "%~1"=="watch" goto watch
python system\run.py %*
set "councilExit=%ERRORLEVEL%"
popd
exit /b %councilExit%
:watch
python system\watch.py %2
set "councilExit=%ERRORLEVEL%"
popd
exit /b %councilExit%
