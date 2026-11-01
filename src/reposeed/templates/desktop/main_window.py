from PySide6.QtWidgets import QLabel, QMainWindow


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("__PROJECT_NAME__")
        self.setCentralWidget(QLabel("__PROJECT_NAME__"))
