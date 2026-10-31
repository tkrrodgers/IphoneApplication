@echo off
rem HERB simulator: creates synthetic data on first run, starts the server and opens the browser.
rem Use Microsoft Edge or Google Chrome for the microphone ("Hi Herb") and HERB's voice.
cd /d "%~dp0"
if not exist data\logsperity.db (
  echo Creating synthetic data...
  python seed.py --reset
)
start "" cmd /c "timeout /t 2 /nobreak >nul & start "" http://localhost:8765"
python server.py
