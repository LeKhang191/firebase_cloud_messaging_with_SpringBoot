@echo off
rem Compatibility wrapper: frontend build logic lives in start.bat.
setlocal
call "%~dp0start.bat" --no-pause --build-frontend --build-only
exit /b %ERRORLEVEL%
