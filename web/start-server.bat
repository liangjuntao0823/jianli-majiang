@echo off
chcp 65001 >nul
cd /d "%~dp0"
title 监利红中 · 局域网麻将

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo  [!] 电脑上还没装 Node.js
  echo      打开 https://nodejs.org/zh-cn 下载 LTS 版本，一路下一步装完再双击我。
  echo.
  pause
  exit /b 1
)

echo.
echo  正在启动局域网麻将...
node server.js
pause
