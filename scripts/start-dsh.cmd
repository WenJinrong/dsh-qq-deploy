@echo off
title DSH Web (127.0.0.1:3080)
set "PATH=__INSTALL_DIR__\node;__INSTALL_DIR__\npm-global;%PATH%"
cd /d "__INSTALL_DIR__"
:loop
echo [%date% %time%] starting dsh web ...
node "__INSTALL_DIR__\npm-global\node_modules\@deepseek-ai\dsh\lib\bin.js" --profile web
echo [%date% %time%] dsh exited (code %errorlevel%), restart in 5s ...
timeout /t 5 /nobreak >nul
goto loop
