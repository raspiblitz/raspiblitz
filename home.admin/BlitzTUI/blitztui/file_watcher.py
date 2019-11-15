import logging
import sys

from PyQt5.QtCore import QThread, pyqtSignal

log = logging.getLogger(__name__)

if sys.platform == "win32":
    log.info("skipping inotify on win32 as it is not supported")
else:
    import inotify.adapters
    import inotify.constants


class FileWatcherThread(QThread):
    signal = pyqtSignal()

    def __init__(self, dir_names, file_names, *args, **kwargs):
        QThread.__init__(self, *args, **kwargs)
        self.dir_names = dir_names
        self.file_names = file_names

    def run(self):
        # run method gets called when we start the thread
        if sys.platform == "win32":
            log.info("skipping inotify on win32 as it is not supported")
            return

        log.info("starting config watcher")
        i = inotify.adapters.Inotify()

        mask = inotify.constants.IN_MODIFY | inotify.constants.IN_CLOSE_WRITE

        for dir_name in self.dir_names:
            i.add_watch(dir_name, mask=mask)

        for event in i.event_gen(yield_nones=False):
            _, type_names, path, filename = event

            log.debug("PATH=[{}] FILENAME=[{}] EVENT_TYPES={}".format(
                path, filename, type_names))

            if path in self.dir_names and filename in self.file_names:
                log.info("watched file was modified/touched")
                self.signal.emit()
