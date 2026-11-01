import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from __PACKAGE_NAME__.ui.main_window import MainWindow


def test_main_window_title() -> None:
    app = QApplication.instance() or QApplication([])
    window = MainWindow()

    assert app is not None
    assert window.windowTitle() == "__PROJECT_NAME__"
