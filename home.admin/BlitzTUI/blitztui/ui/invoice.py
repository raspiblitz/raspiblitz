# -*- coding: utf-8 -*-

# Form implementation generated from reading ui file 'designer/invoice.ui'
#
# Created by: PyQt5 UI code generator 5.11.3
#
# WARNING! All changes made in this file will be lost!

from PyQt5 import QtCore, QtGui, QtWidgets

class Ui_DialogSelectInvoice(object):
    def setupUi(self, DialogSelectInvoice):
        DialogSelectInvoice.setObjectName("DialogSelectInvoice")
        DialogSelectInvoice.resize(480, 320)
        sizePolicy = QtWidgets.QSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(DialogSelectInvoice.sizePolicy().hasHeightForWidth())
        DialogSelectInvoice.setSizePolicy(sizePolicy)
        DialogSelectInvoice.setStyleSheet("")
        self.buttonBox = QtWidgets.QDialogButtonBox(DialogSelectInvoice)
        self.buttonBox.setGeometry(QtCore.QRect(102, 110, 320, 340))
        sizePolicy = QtWidgets.QSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.buttonBox.sizePolicy().hasHeightForWidth())
        self.buttonBox.setSizePolicy(sizePolicy)
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
        self.buttonBox.setStandardButtons(QtWidgets.QDialogButtonBox.Cancel|QtWidgets.QDialogButtonBox.Ok|QtWidgets.QDialogButtonBox.Yes)
        self.buttonBox.setObjectName("buttonBox")
        self.label = QtWidgets.QLabel(DialogSelectInvoice)
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
        self.label_2 = QtWidgets.QLabel(DialogSelectInvoice)
        self.label_2.setGeometry(QtCore.QRect(0, 0, 47, 318))
        self.label_2.setText("")
        self.label_2.setPixmap(QtGui.QPixmap(":/RaspiBlitz/images/RaspiBlitz_Logo_Main_270.png"))
        self.label_2.setScaledContents(True)
        self.label_2.setObjectName("label_2")

        self.retranslateUi(DialogSelectInvoice)
        self.buttonBox.accepted.connect(DialogSelectInvoice.accept)
        self.buttonBox.rejected.connect(DialogSelectInvoice.reject)
        QtCore.QMetaObject.connectSlotsByName(DialogSelectInvoice)

    def retranslateUi(self, DialogSelectInvoice):
        _translate = QtCore.QCoreApplication.translate
        DialogSelectInvoice.setWindowTitle(_translate("DialogSelectInvoice", "Dialog"))
        self.label.setText(_translate("DialogSelectInvoice", "Select Invoice"))

from . import resources_rc

if __name__ == "__main__":
    import sys
    app = QtWidgets.QApplication(sys.argv)
    DialogSelectInvoice = QtWidgets.QDialog()
    ui = Ui_DialogSelectInvoice()
    ui.setupUi(DialogSelectInvoice)
    DialogSelectInvoice.show()
    sys.exit(app.exec_())

