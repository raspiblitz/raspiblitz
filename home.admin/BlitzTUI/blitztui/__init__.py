# -*- coding: utf-8 -*-

import logging
from blitztui.version import __version__
from blitztui.file_logger import setup_logging

log = logging.getLogger()
setup_logging()
log.info("Starting BlitzTUI v{}".format(__version__))
