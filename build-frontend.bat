@echo off
rem Builds the React UI (frontend\) and copies it into Spring Boot's static folder.
setlocal
set ROOT=%~dp0
set STATIC=%ROOT%src\main\resources\static
where npm >nul 2>nul || (echo Need Node.js 18+ ^(npm not found^) & exit /b 1)
pushd "%ROOT%frontend" || exit /b 1
call npm install --no-audit --no-fund || (popd & exit /b 1)
call npm run build || (popd & exit /b 1)
if exist "%STATIC%\assets" rmdir /s /q "%STATIC%\assets"
xcopy /e /y /i "dist\*" "%STATIC%\" >nul
popd
echo Done. Reload the page to see the new UI.
endlocal
