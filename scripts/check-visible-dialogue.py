"""Run the same real-window fixture as GameLingo.exe --window-test REPORT.json."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"desktop"))
from PySide6.QtWidgets import QApplication
from gamelingo.dialogue_check import verify_window

if __name__=="__main__":
    raise SystemExit(verify_window(sys.argv[1],QApplication([])))
