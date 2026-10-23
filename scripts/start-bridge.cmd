@echo off
title QQ-Bridge (3100)
set "PATH=__INSTALL_DIR__\node;__INSTALL_DIR__\npm-global;%PATH%"
cd /d "__INSTALL_DIR__\qq-bridge"
echo waiting for DSH on 127.0.0.1:3080 ...
set /a n=0
:waitdsh
powershell -NoProfile -Command "try{(New-Object Net.Sockets.TcpClient).Connect('127.0.0.1',3080);exit 0}catch{exit 1}" >nul 2>&1
if %errorlevel%==0 goto dshok
set /a n+=1
if %n% geq 60 (
  echo [WARN] DSH not ready, starting bridge anyway
  goto dshok
)
timeout /t 3 /nobreak >nul
goto waitdsh
:dshok
node "scripts\harden-state-acl.mjs" --quiet >nul 2>&1
:loop
echo [%date% %time%] starting bridge ...
node "src\bridge.js"
set code=%errorlevel%
if "%code%"=="2" (
  echo another bridge instance is running, exit.
  pause
  exit /b 2
)
echo [%date% %time%] bridge exited (code %code%), restart in 5s ...
timeout /t 5 /nobreak >nul
goto loop