#!/usr/bin/env python
# -*- coding: utf-8 -*-

import argparse
import itertools
import logging
import os
import signal
import sys
import time
from argparse import RawTextHelpFormatter
from functools import lru_cache
from io import BytesIO
from threading import Event

import qrcode
from PyQt5.QtCore import Qt, QProcess, QThread, pyqtSignal, QCoreApplication, QTimer, QEventLoop
from PyQt5.QtGui import QPixmap
from PyQt5.QtWidgets import QMainWindow, QApplication, QDialog, QDialogButtonBox
from blitztui.client import ReadOnlyStub, InvoiceStub
from blitztui.client import check_lnd, check_lnd_channels
from blitztui.client import check_invoice_paid, create_invoice, get_node_uri
from blitztui.client import convert_r_hash_hex_bytes
from blitztui.config import LndConfig, RaspiBlitzConfig, RaspiBlitzInfo
from blitztui.file_watcher import FileWatcherThread
from blitztui.memo import adjective_noun_pair
from blitztui.version import __version__
from blitztui.ui.home import Ui_MainWindow
from blitztui.ui.invoice import Ui_DialogSelectInvoice
from blitztui.ui.off import Ui_DialogConfirmOff
from blitztui.ui.qcode import Ui_DialogShowQrCode
from pyqtspinner.spinner import WaitingSpinner

log = logging.getLogger()

IS_DEV_ENV = os.getenv('RASPIBLITZ_DEV', '0').lower() in ['1', 'true', 't', 'y', 'yes', 'on']
IS_WIN32_ENV = sys.platform == "win32"

SCREEN_HEIGHT = 318

LND_CONF = "/mnt/hdd/lnd/lnd.conf"
RB_CONF = "/mnt/hdd/raspiblitz.conf"
RB_INFO = "/home/admin/raspiblitz.info"

STATUS_INTERVAL_LND = 30
STATUS_INTERVAL_LND_CHANNELS = 120
INVOICE_CHECK_TIMEOUT = 1800
INVOICE_CHECK_INTERVAL = 2.0  # 1800*2.0s == 3600s == 1 Hour during which the invoice is monitored

SCREEN_NODE_URI = "Node URI"
SCREEN_INVOICE = "Invoice"


class AppWindow(QMainWindow):
    def __init__(self, *args, **kwargs):
        super(AppWindow, self).__init__(*args, **kwargs)
        self.ui = Ui_MainWindow()
        self.ui.setupUi(self)

        # translations..?!
        self._translate = QCoreApplication.translate

        if IS_WIN32_ENV:
            log.info("using dummy config on win32")
            lnd_cfg_abs_path = os.path.join(os.path.dirname(__file__), "..", "data", os.path.basename(LND_CONF))
            rb_cfg_abs_path = os.path.join(os.path.dirname(__file__), "..", "data", os.path.basename(RB_CONF))
            rb_info_abs_path = os.path.join(os.path.dirname(__file__), "..", "data", os.path.basename(RB_INFO))
        else:
            lnd_cfg_abs_path = LND_CONF
            rb_cfg_abs_path = RB_CONF
            rb_info_abs_path = RB_INFO

        # read config and info files
        if not os.path.exists(lnd_cfg_abs_path):
            log.error("file does not exist: {}".format(lnd_cfg_abs_path))
            raise Exception("file does not exist: {}".format(lnd_cfg_abs_path))

        if not os.path.exists(rb_cfg_abs_path):
            log.error("file does not exist: {}".format(rb_cfg_abs_path))
            raise Exception("file does not exist: {}".format(rb_cfg_abs_path))

        if not os.path.exists(rb_info_abs_path):
            log.error("file does not exist: {}".format(rb_info_abs_path))
            raise Exception("file does not exist: {}".format(rb_info_abs_path))

        self.lnd_cfg = LndConfig(lnd_cfg_abs_path)
        self.lnd_cfg.reload()

        self.rb_cfg = RaspiBlitzConfig(rb_cfg_abs_path)
        self.rb_cfg.reload()

        self.rb_info = RaspiBlitzInfo(rb_info_abs_path)
        self.rb_info.reload()

        # initialize attributes
        self.invoice_to_check = None
        self.invoice_to_check_flag = None

        self.uptime = 0

        self.status_lnd_due = 0
        self.status_lnd_interval = STATUS_INTERVAL_LND
        self.status_lnd_pid_ok = False
        self.status_lnd_listen_ok = False
        self.status_lnd_unlocked = False
        self.status_lnd_synced_to_chain = False
        self.status_lnd_synced_to_graph = False

        self.status_lnd_channel_due = 0
        self.status_lnd_channel_interval = STATUS_INTERVAL_LND_CHANNELS
        self.status_lnd_channel_total_active = 0
        self.status_lnd_channel_total_remote_balance = 0

        # initial updates
        self.update_uptime()
        self.update_status_lnd()
        self.update_status_lnd_channels()

        # initial update of Main Window Title Bar
        self.update_title_bar()

        # Align Main Window Top Left
        self.move(0, 0)

        # set as maximized (unless on Windows dev host)
        if IS_WIN32_ENV:
            log.info("not maximizing window on win32")
        else:
            self.setWindowState(Qt.WindowMaximized)

        # Bindings: buttons
        self.ui.pushButton_1.clicked.connect(self.on_button_1_clicked)
        self.ui.pushButton_2.clicked.connect(self.on_button_2_clicked)
        self.ui.pushButton_3.clicked.connect(self.on_button_3_clicked)
        self.ui.pushButton_4.clicked.connect(self.on_button_4_clicked)

        # disable button 1 for now
        self.ui.pushButton_1.setEnabled(False)

        # connect error dismiss button and hide for start
        self.ui.buttonBox_close.button(QDialogButtonBox.Close).setText("Ok")
        self.ui.buttonBox_close.button(QDialogButtonBox.Close).clicked.connect(self.hide_error)
        self.hide_error()

        # Show QR Code Dialog Windows
        self.w_qr_code = QDialog(flags=(Qt.Dialog | Qt.FramelessWindowHint))
        self.ui_qr_code = Ui_DialogShowQrCode()
        self.ui_qr_code.setupUi(self.w_qr_code)
        self.w_qr_code.move(0, 0)

        # SPINNER for CR Code Dialog Window
        self.ui_qr_code.spinner = WaitingSpinner(self.w_qr_code)

        self.beat_thread = BeatThread()
        self.beat_thread.signal.connect(self.process_beat)
        self.beat_thread.start()

        self.generate_qr_code_thread = GenerateQrCodeThread()
        self.generate_qr_code_thread.signal.connect(self.generate_qr_code_finished)

        self.file_watcher = FileWatcherThread(
            dir_names=[os.path.dirname(LND_CONF), os.path.dirname(RB_CONF), os.path.dirname(RB_INFO)],
            file_names=[os.path.basename(LND_CONF), os.path.basename(RB_CONF), os.path.basename(RB_INFO)],
        )
        self.file_watcher.signal.connect(self.update_watched_attr)
        self.file_watcher.start()

        # finally start 00infoBlitz.sh in dedicated xterm frame
        self.start_info_lcd()

        self.show()

    def start_info_lcd(self, pause=12):
        # if system has been running for more than 90 seconds then skip pause
        if self.uptime > 90:
            pause = 0

        process = QProcess(self)
        process.setProcessChannelMode(QProcess.MergedChannels)
        # connect the stdout_item to the Process StandardOutput
        # it gets constantly update as the process emit std output
        process.readyReadStandardOutput.connect(
            lambda: log.info(str(process.readAllStandardOutput().data().decode('utf-8'))))

        process.start('xterm', ['-fn', 'fixed', '-into', str(int(self.ui.widget.winId())),
                                '+sb', '-hold', '-e', 'bash -c \"/home/admin/00infoLCD.sh --pause {}\"'.format(pause)])

    def check_invoice(self, flag, tick=0):
        log.info("checking invoice paid (Tick: {})".format(tick))
        self.invoice_to_check_flag = flag

        if tick >= INVOICE_CHECK_TIMEOUT:
            log.debug("canceled checking invoice paid")
            flag.set()

        if IS_DEV_ENV:
            res = False
            amt_paid_sat = 123123402

            if tick == 5:
                res = True

        else:
            stub_readonly = ReadOnlyStub(network=self.rb_cfg.network, chain=self.rb_cfg.chain)
            res, amt_paid_sat = check_invoice_paid(stub_readonly, self.invoice_to_check)
            log.debug("result of invoice check: {}".format(res))

        if res:
            log.debug("paid!")
            self.ui_qr_code.qcode.setMargin(8)
            self.ui_qr_code.qcode.setPixmap(QPixmap(":/RaspiBlitz/images/Paid_Stamp.png"))

            if amt_paid_sat:
                self.ui_qr_code.status_value.setText("Paid")
                self.ui_qr_code.amt_paid_value.setText("{}".format(amt_paid_sat))
            else:
                self.ui_qr_code.status_value.setText("Paid")

            flag.set()

    def update_status_lnd(self):
        if IS_WIN32_ENV:
            return

        # log.debug("update_status_lnd due: {}".format(self.status_lnd_due))
        if self.status_lnd_due <= self.uptime:
            log.debug("updating status_lnd")
            stub_readonly = ReadOnlyStub(network=self.rb_cfg.network, chain=self.rb_cfg.chain)
            pid_ok, listen_ok, unlocked, synced_to_chain, synced_to_graph = check_lnd(stub_readonly)
            self.status_lnd_pid_ok = pid_ok
            self.status_lnd_listen_ok = listen_ok
            self.status_lnd_unlocked = unlocked
            self.status_lnd_synced_to_chain = synced_to_chain
            self.status_lnd_synced_to_graph = synced_to_graph
            # set next due time
            self.status_lnd_due = self.uptime + self.status_lnd_interval

    def update_status_lnd_channels(self):
        if IS_WIN32_ENV:
            return

        # log.debug("update_status_lnd_channel due: {}".format(self.status_lnd_channel_due))
        if self.status_lnd_channel_due <= self.uptime:
            log.debug("updating status_lnd_channels")
            stub_readonly = ReadOnlyStub(network=self.rb_cfg.network, chain=self.rb_cfg.chain)
            self.status_lnd_channel_total_active, self.status_lnd_channel_total_remote_balance = \
                check_lnd_channels(stub_readonly)
            # set next due time
            self.status_lnd_channel_due = self.uptime + self.status_lnd_channel_interval

    def update_title_bar(self):
        log.debug("updating: Main Window Title Bar")
        self.setWindowTitle(self._translate("MainWindow", "RaspiBlitz v{} - {} - {}net".format(self.rb_cfg.version,
                                                                                               self.rb_cfg.network,
                                                                                               self.rb_cfg.chain)))

    def update_uptime(self):
        if IS_WIN32_ENV:
            self.uptime += 1
        else:
            with open('/proc/uptime', 'r') as f:
                self.uptime = float(f.readline().split()[0])
            # log.info("Uptime: {}".format(self.uptime))

    def process_beat(self, _):
        self.update_uptime()
        self.update_status_lnd()
        self.update_status_lnd_channels()

    def update_watched_attr(self):
        log.debug("updating: watched attributes")
        self.lnd_cfg.reload()
        self.rb_cfg.reload()
        self.rb_info.reload()

        # add anything here that should be updated now too
        self.update_title_bar()

    def hide_error(self):
        self.ui.error_label.hide()
        self.ui.buttonBox_close.hide()

    def show_qr_code(self, data, screen=None, memo=None, status=None, inv_amt=None, amt_paid="N/A"):
        log.debug("show_qr_code: {}".format(data))
        # reset to logo and set text
        self.ui_qr_code.qcode.setMargin(48)
        self.ui_qr_code.qcode.setPixmap(QPixmap(":/RaspiBlitz/images/RaspiBlitz_Logo_Stacked.png"))

        if screen == SCREEN_NODE_URI:
            self.ui_qr_code.memo_key.show()
            self.ui_qr_code.memo_key.setText("Node URI")

            _tmp = data.split("@")
            pub = _tmp[0]
            _tmp2 = _tmp[1].split(":")
            host = _tmp2[0]
            port = _tmp2[1]

            n = 16
            pub = [(pub[i:i + n]) for i in range(0, len(pub), n)]
            host = [(host[i:i + n]) for i in range(0, len(host), n)]
            self.ui_qr_code.memo_value.show()
            self.ui_qr_code.memo_value.setText("{} \n@\n{} \n:{}".format(" ".join(pub), " ".join(host), port))

            self.ui_qr_code.status_key.hide()
            self.ui_qr_code.status_value.hide()
            self.ui_qr_code.inv_amt_key.hide()
            self.ui_qr_code.inv_amt_value.hide()
            self.ui_qr_code.amt_paid_key.hide()
            self.ui_qr_code.amt_paid_value.hide()

        if screen == SCREEN_INVOICE:
            self.ui_qr_code.memo_key.show()
            self.ui_qr_code.memo_key.setText("Invoice Memo")

            self.ui_qr_code.memo_value.show()
            self.ui_qr_code.memo_value.setText(memo)

            self.ui_qr_code.status_key.show()
            self.ui_qr_code.status_value.show()
            self.ui_qr_code.status_value.setText(status)

            self.ui_qr_code.inv_amt_key.show()
            self.ui_qr_code.inv_amt_value.show()
            self.ui_qr_code.inv_amt_value.setText("{}".format(inv_amt))

            self.ui_qr_code.amt_paid_key.show()
            self.ui_qr_code.amt_paid_value.show()
            self.ui_qr_code.amt_paid_value.setText("{}".format(amt_paid))

        # set function and start thread
        self.generate_qr_code_thread.data = data
        self.generate_qr_code_thread.start()
        self.ui_qr_code.spinner.start()

        self.w_qr_code.activateWindow()
        self.w_qr_code.show()

        rsp = self.w_qr_code.exec_()
        if rsp == QDialog.Accepted:
            log.info("QR: pressed OK - canceling invoice check")
            if self.invoice_to_check_flag:
                self.invoice_to_check_flag.set()

    def generate_qr_code_finished(self, img):
        buf = BytesIO()
        img.save(buf, "PNG")

        qt_pixmap = QPixmap()
        qt_pixmap.loadFromData(buf.getvalue(), "PNG")
        self.ui_qr_code.spinner.stop()
        self.ui_qr_code.qcode.setMargin(2)
        self.ui_qr_code.qcode.setPixmap(qt_pixmap)

    def on_button_1_clicked(self):
        log.debug("clicked: B1: {}".format(self.winId()))
        # self.start_info_lcd(pause=0)

    def on_button_2_clicked(self):
        log.debug("clicked: B2: {}".format(self.winId()))

        if not (self.status_lnd_pid_ok and self.status_lnd_listen_ok):
            log.warning("LND is not ready")
            self.ui.error_label.show()
            self.ui.error_label.setText("Err: LND is not ready!")
            self.ui.buttonBox_close.show()
            return

        if not self.status_lnd_unlocked:
            log.warning("LND is locked")
            self.ui.error_label.show()
            self.ui.error_label.setText("Err: LND is locked")
            self.ui.buttonBox_close.show()
            return

        data = self.get_node_uri()
        if data:
            self.show_qr_code(data, SCREEN_NODE_URI)
        else:
            log.warning("Node URI is none!")
            # TODO(frennkie) inform user

    def on_button_3_clicked(self):
        log.debug("clicked: B3: {}".format(self.winId()))

        if not (self.status_lnd_pid_ok and self.status_lnd_listen_ok):
            log.warning("LND is not ready")
            self.ui.error_label.show()
            self.ui.error_label.setText("Err: LND is not ready!")
            self.ui.buttonBox_close.show()
            return

        if not self.status_lnd_unlocked:
            log.warning("LND is locked")
            self.ui.error_label.show()
            self.ui.error_label.setText("Err: LND is locked")
            self.ui.buttonBox_close.show()
            return

        if not self.status_lnd_channel_total_active:
            log.warning("not creating invoice: unable to receive - no open channels")
            self.ui.error_label.show()
            self.ui.error_label.setText("Err: No open channels!")
            self.ui.buttonBox_close.show()
            return

        if not self.status_lnd_channel_total_remote_balance:
            log.warning("not creating invoice: unable to receive - no remote capacity on any channel")
            self.ui.error_label.show()
            self.ui.error_label.setText("Err: No remote capacity!")
            self.ui.buttonBox_close.show()
            return

        dialog_b1 = QDialog(flags=(Qt.Dialog | Qt.FramelessWindowHint))
        ui = Ui_DialogSelectInvoice()
        ui.setupUi(dialog_b1)

        dialog_b1.move(0, 0)

        ui.buttonBox.button(QDialogButtonBox.Yes).setText("{} SAT".format(self.rb_cfg.invoice_default_amount))
        ui.buttonBox.button(QDialogButtonBox.Ok).setText("Donation")
        if self.rb_cfg.invoice_allow_donations:
            ui.buttonBox.button(QDialogButtonBox.Ok).setEnabled(True)
        else:
            ui.buttonBox.button(QDialogButtonBox.Ok).setEnabled(False)

        ui.buttonBox.button(QDialogButtonBox.Cancel).setText("Cancel")

        ui.buttonBox.button(QDialogButtonBox.Yes).clicked.connect(self.b3_invoice_set_amt)
        ui.buttonBox.button(QDialogButtonBox.Ok).clicked.connect(self.b3_invoice_custom_amt)

        dialog_b1.show()

        rsp = dialog_b1.exec_()
        if not rsp == QDialog.Accepted:
            log.info("B3: pressed is: Cancel")

    def b3_invoice_set_amt(self):
        log.info("b1 option: set amount")

        check_invoice_thread = ClockStoppableThread(Event(), interval=INVOICE_CHECK_INTERVAL)
        check_invoice_thread.signal.connect(self.check_invoice)
        check_invoice_thread.start()

        a, n = adjective_noun_pair()
        inv_memo = "RB-{}-{}".format(a.capitalize(), n.capitalize())

        new_invoice = self.create_new_invoice(inv_memo, amt=self.rb_cfg.invoice_default_amount)
        data = new_invoice.payment_request
        self.show_qr_code(data, SCREEN_INVOICE, memo=inv_memo, status="Open",
                          inv_amt=self.rb_cfg.invoice_default_amount)

    def b3_invoice_custom_amt(self):
        log.info("b1 option: custom amount")

        check_invoice_thread = ClockStoppableThread(Event(), interval=INVOICE_CHECK_INTERVAL)
        check_invoice_thread.signal.connect(self.check_invoice)
        check_invoice_thread.start()

        a, n = adjective_noun_pair()
        inv_memo = "RB-{}-{}".format(a.capitalize(), n.capitalize())

        new_invoice = self.create_new_invoice(inv_memo, amt=0)
        data = new_invoice.payment_request
        self.show_qr_code(data, SCREEN_INVOICE, memo=inv_memo, status="Open", inv_amt="Donation")

    def on_button_4_clicked(self):
        log.debug("clicked: B4: {}".format(self.winId()))

        dialog_b4 = QDialog(flags=(Qt.Dialog | Qt.FramelessWindowHint))
        ui = Ui_DialogConfirmOff()
        ui.setupUi(dialog_b4)

        dialog_b4.move(0, 0)

        ui.buttonBox.button(QDialogButtonBox.Yes).setText("Shutdown")
        ui.buttonBox.button(QDialogButtonBox.Retry).setText("Restart")
        ui.buttonBox.button(QDialogButtonBox.Cancel).setText("Cancel")

        ui.buttonBox.button(QDialogButtonBox.Yes).clicked.connect(self.b4_shutdown)
        ui.buttonBox.button(QDialogButtonBox.Retry).clicked.connect(self.b4_restart)

        dialog_b4.show()
        rsp = dialog_b4.exec_()

        if rsp == QDialog.Accepted:
            log.info("B4: pressed is: Accepted - Shutdown or Restart")
        else:
            log.info("B4: pressed is: Cancel")

    def b4_shutdown(self):
        log.info("shutdown")
        if IS_WIN32_ENV:
            log.info("skipping on win32")
            return

        process = QProcess(self)
        process.start('xterm', ['-fn', 'fixed', '-into', str(int(self.ui.widget.winId())),
                                '+sb', '-hold', '-e', 'bash -c \"sudo /home/admin/XXshutdown.sh\"'])

    def b4_restart(self):
        log.info("restart")
        if IS_WIN32_ENV:
            log.info("skipping on win32")
            return

        process = QProcess(self)
        process.start('xterm', ['-fn', 'fixed', '-into', str(int(self.ui.widget.winId())),
                                '+sb', '-hold', '-e', 'bash -c \"sudo /home/admin/XXshutdown.sh reboot\"'])

    def create_new_invoice(self, memo="Pay to RaspiBlitz", amt=0):
        if IS_DEV_ENV:
            # Fake an invoice for dev
            class FakeAddInvoiceResponse(object):
                def __init__(self):
                    self.add_index = 145
                    self.payment_request = "lnbc47110n1pwmfqcdpp5k55n5erv60mg6u4c8s3qggnw3dsn267e80ypjxxp6gj593" \
                                           "p3c25sdq9vehk7cqzpgprn0ytv6ukxc2vclgag38nmsmlyggmd4zand9qay2l3gc5at" \
                                           "ecxjynydyzhvxsysam9d46y5lgezh2nkufvn23403t3tz3lyhd070dgq625xp0"
                    self.r_hash = b'\xf9\xe3(\xf5\x84\xdad\x88\xe4%\xa7\x1c\x95\xbe\x8baJ\x1c\xc1\xad*\xed\xc8' \
                                  b'\x158\x13\xdf\xffF\x9c\x95\x84'

            new_invoice = FakeAddInvoiceResponse()

        else:
            stub_invoice = InvoiceStub(network=self.rb_cfg.network, chain=self.rb_cfg.chain)
            new_invoice = create_invoice(stub_invoice, memo, amt)

        log.info("#{}: {}".format(new_invoice.add_index, new_invoice.payment_request))

        invoice_r_hash_hex_str = convert_r_hash_hex_bytes(new_invoice.r_hash)
        self.invoice_to_check = invoice_r_hash_hex_str
        log.info("noting down for checking: {}".format(invoice_r_hash_hex_str))

        return new_invoice

    def get_node_uri(self):
        if IS_DEV_ENV:
            return "535f209faaea75427949e3e6c1fc9edafbf751f08706506bb873fdc93ffc2d4e2c@pqcjuc47eqcv6mk2.onion:9735"

        stub_readonly = ReadOnlyStub(network=self.rb_cfg.network, chain=self.rb_cfg.chain)

        res = get_node_uri(stub_readonly)
        log.info("Node URI: : {}".format(res))

        return res


class ClockStoppableThread(QThread):
    signal = pyqtSignal('PyQt_PyObject', 'PyQt_PyObject')

    def __init__(self, event, interval=0.5, *args, **kwargs):
        QThread.__init__(self, *args, **kwargs)

        self.stopped = event
        self.interval = interval
        # atomic (?!) counter
        self.ctr = itertools.count()

    def run(self):
        log.info("starting stoppable clock")
        while not self.stopped.wait(self.interval):
            self.signal.emit(self.stopped, next(self.ctr))


class GenerateQrCodeThread(QThread):
    signal = pyqtSignal('PyQt_PyObject')

    def __init__(self):
        QThread.__init__(self)
        self.data = None

    def run(self):
        # run method gets called when we start the thread
        img = get_qr_img(self.data)
        # done, now inform the main thread with the output
        self.signal.emit(img)


class BeatThread(QThread):
    signal = pyqtSignal('PyQt_PyObject')

    def __init__(self, interval=5000, *args, **kwargs):
        QThread.__init__(self, *args, **kwargs)

        self.interval = interval

        self.beat_timer = QTimer()
        self.beat_timer.moveToThread(self)
        self.beat_timer.timeout.connect(self.tick)

    def tick(self):
        # log.debug("beat")
        self.signal.emit(0)

    def run(self):
        log.info("starting beat")
        self.beat_timer.start(self.interval)
        loop = QEventLoop()
        loop.exec_()


@lru_cache(maxsize=32)
def get_qr_img(data):
    for i in range(6, 1, -1):
        time.sleep(1.0)
        qr_img = qrcode.make(data, box_size=i)
        log.info("Box Size: {}, Image Size: {}".format(i, qr_img.size[0]))
        if qr_img.size[0] <= SCREEN_HEIGHT:
            break
    else:
        raise Exception("none found")
    return qr_img


def main():
    # make sure CTRL+C works
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    description = """BlitzTUI - the Touch-User-Interface for the RaspiBlitz project

Keep on stacking SATs..! :-D"""

    parser = argparse.ArgumentParser(description=description, formatter_class=RawTextHelpFormatter)
    parser.add_argument("-V", "--version",
                        help="print version", action="version",
                        version=__version__)
    #
    # parser.add_argument("-g", "--game",
    #                     help="game binary", type=str)
    #
    # parser.add_argument("-s", "--skip",
    #                     help="skip", action="store_true")

    # parse args
    args = parser.parse_args()

    # initialize app
    app = QApplication(sys.argv)

    w = AppWindow()
    w.show()

    # run app
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
