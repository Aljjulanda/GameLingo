import sys
from PySide6.QtCore import Qt,QTimer
from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QIcon
from pathlib import Path
from gamelingo.ui import MainWindow

STYLE = """
QMainWindow, QWidget { background: #132429; color: #edf7f5; font: 11pt 'Segoe UI'; }
QLabel#brand { font: 600 26pt 'Segoe UI'; color: #68e2bc; padding: 4px 12px; }
QLabel#subtitle { background: #1c3339; padding: 20px; border-radius: 8px; font: 18pt 'Segoe UI'; }
QTabBar::tab, QPushButton { background: #214048; padding: 7px 13px; border: 1px solid #38535a; border-radius: 4px; }
QTabBar::tab:selected, QPushButton:hover { background: #2c555c; }
QPushButton:focus, QComboBox:focus { border: 2px solid #64dfbb; }
QPushButton:disabled { color: #93a4a4; background: #203138; }
QLineEdit, QComboBox, QSpinBox, QPlainTextEdit { background: #0e1f24; padding: 4px; border: 1px solid #3f5c62; }
QFormLayout { margin: 12px; }
"""
if __name__ == "__main__":
    app=QApplication(sys.argv)
    if len(sys.argv)==3 and sys.argv[1]=="--window-test":
        from gamelingo.dialogue_check import verify_window
        sys.exit(verify_window(sys.argv[2],app))
    app.setApplicationName("GameLingo")
    icon=Path(__file__).with_name("GameLingo.ico")
    if icon.exists():app.setWindowIcon(QIcon(str(icon)))
    app.setStyleSheet(STYLE)
    window=MainWindow()
    if len(sys.argv)==3 and sys.argv[1]=="--self-test":
        from gamelingo.diagnostics import self_test
        sys.exit(self_test(sys.argv[2],window))
    window.show()
    if '--start-translation' in sys.argv:QTimer.singleShot(0,window.start_saved_session)
    sys.exit(app.exec())

