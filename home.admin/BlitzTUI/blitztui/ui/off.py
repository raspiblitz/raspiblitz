# -*- coding: utf-8 -*-

# Form implementation generated from reading ui file 'designer/off.ui'
#
# Created by: PyQt5 UI code generator 5.11.3
#
# WARNING! All changes made in this file will be lost!

from PyQt5 import QtCore, QtGui, QtWidgets

class Ui_DialogConfirmOff(object):
    def setupUi(self, DialogConfirmOff):
        DialogConfirmOff.setObjectName("DialogConfirmOff")
        DialogConfirmOff.resize(480, 320)
        DialogConfirmOff.setStyleSheet("background-color: rgb(255, 128, 128)")
        self.label_2 = QtWidgets.QLabel(DialogConfirmOff)
        self.label_2.setGeometry(QtCore.QRect(9, 9, 16, 16))
        self.label_2.setMaximumSize(QtCore.QSize(110, 320))
        self.label_2.setText("")
        self.label_2.setPixmap(QtGui.QPixmap(":/RaspiBlitz/images/RaspiBlitz_Logo_Main_rotate.png"))
        self.label_2.setScaledContents(True)
        self.label_2.setIndent(-4)
        self.label_2.setObjectName("label_2")
        self.label_3 = QtWidgets.QLabel(DialogConfirmOff)
        self.label_3.setGeometry(QtCore.QRect(0, 0, 47, 318))
        self.label_3.setText("")
        self.label_3.setPixmap(QtGui.QPixmap(":/RaspiBlitz/images/RaspiBlitz_Logo_Main_270.png"))
        self.label_3.setScaledContents(True)
        self.label_3.setObjectName("label_3")
        self.label = QtWidgets.QLabel(DialogConfirmOff)
        self.label.setGeometry(QtCore.QRect(102, 30, 320, 64))
        font = QtGui.QFont()
        font.setFamily("Arial")
        font.setPointSize(20)
        font.setBold(False)
        font.setItalic(False)
        font.setWeight(50)
        self.label.setFont(font)
        self.label.setStyleSheet("")
        self.label.setAlignment(QtCore.Qt.AlignHCenter|QtCore.Qt.AlignTop)
        self.label.setObjectName("label")
        self.buttonBox = QtWidgets.QDialogButtonBox(DialogConfirmOff)
        self.buttonBox.setGeometry(QtCore.QRect(102, 110, 320, 340))
        sizePolicy = QtWidgets.QSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.buttonBox.sizePolicy().hasHeightForWidth())
        self.buttonBox.setSizePolicy(sizePolicy)
        self.buttonBox.setMinimumSize(QtCore.QSize(0, 0))
        self.buttonBox.setMaximumSize(QtCore.QSize(16777215, 16777215))
        font = QtGui.QFont()
        font.setFamily("Arial")
        font.setPointSize(28)
        font.setBold(False)
        font.setItalic(False)
        font.setWeight(50)
        self.buttonBox.setFont(font)
        self.buttonBox.setStyleSheet("background-color: lightgrey;\n"
"font: 28pt \"Arial\";")
        self.buttonBox.setOrientation(QtCore.Qt.Vertical)
        self.buttonBox.setStandardButtons(QtWidgets.QDialogButtonBox.Cancel|QtWidgets.QDialogButtonBox.Retry|QtWidgets.QDialogButtonBox.Yes)
        self.buttonBox.setObjectName("buttonBox")

        self.retranslateUi(DialogConfirmOff)
        self.buttonBox.rejected.connect(DialogConfirmOff.reject)
        self.buttonBox.accepted.connect(DialogConfirmOff.accept)
        QtCore.QMetaObject.connectSlotsByName(DialogConfirmOff)

    def retranslateUi(self, DialogConfirmOff):
        _translate = QtCore.QCoreApplication.translate
        DialogConfirmOff.setWindowTitle(_translate("DialogConfirmOff", "Dialog"))
        self.label.setText(_translate("DialogConfirmOff", "Shutdown RaspiBlitz?"))

from . import resources_rc

if __name__ == "__main__":
    import sys
    app = QtWidgets.QApplication(sys.argv)
    DialogConfirmOff = QtWidgets.QDialog()
    ui = Ui_DialogConfirmOff()
    ui.setupUi(DialogConfirmOff)
    DialogConfirmOff.show()
    sys.exit(app.exec_())

