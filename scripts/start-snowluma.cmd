@echo off
title SnowLuma 2.x (WebUI 5099)
set "PATH=__INSTALL_DIR__\SnowLuma;__INSTALL_DIR__\node;%PATH%"
cd /d "__INSTALL_DIR__\SnowLuma"
if not exist "index.mjs" (
  echo [ERROR] SnowLuma not installed: __INSTALL_DIR__\SnowLuma
  pause
  exit /b 1
)
:loop
echo [%date% %time%] starting SnowLuma ...
node ".\index.mjs"
echo [%date% %time%] SnowLuma exited (code %errorlevel%), restart in 5s ...
timeout /t 5 /nobreak >nul
goto loop