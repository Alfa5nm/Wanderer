@echo off
set "CURIOSITY_GODOT=D:\Softwares\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
if not exist "%CURIOSITY_GODOT%" (
  echo Edit Run.cmd to point to your Godot 4.6 executable.
  pause
  exit /b 1
)
"%CURIOSITY_GODOT%" --path "%~dp0."
