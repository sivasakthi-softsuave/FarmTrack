@echo off
rem Shows the USB-connected Android phone's screen in a window on this PC (scrcpy), so changes made in VS Code
rem (hot reload) can be seen without looking at the phone. Keep the phone unlocked and plugged in.
rem Needs: USB debugging on, and scrcpy installed with:  winget install Genymobile.scrcpy
set "ADB=C:\siva\tools\android-sdk\platform-tools\adb.exe"
set "SCRCPY=%LOCALAPPDATA%\Microsoft\WinGet\Packages\Genymobile.scrcpy_Microsoft.Winget.Source_8wekyb3d8bbwe\scrcpy-win64-v5.0.1\scrcpy.exe"
if not exist "%SCRCPY%" (
  echo scrcpy not found at %SCRCPY%
  echo Install it with: winget install Genymobile.scrcpy
  exit /b 1
)
"%SCRCPY%" --window-title "FarmTrack phone" --stay-awake
