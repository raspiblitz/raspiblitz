import getpass
import json
import logging
import logging.config
import os
import sys

IS_WIN32_ENV = sys.platform == "win32"


def setup_logging(default_path=os.path.abspath(os.path.expanduser('~/.blitz-tui.json')), log_level="INFO"):
    """Setup logging configuration"""
    path = default_path
    if os.path.exists(path):
        with open(path, 'rt') as f:
            config = json.load(f)
        logging.config.dictConfig(config)

    else:  # if $default_path does not exist use the following default log setup

        if IS_WIN32_ENV:
            log_file = "blitz-tui.log"
        else:
            if os.path.isdir('/var/cache/raspiblitz'):
                try:
                    os.mkdir('/var/cache/raspiblitz/{}'.format(getpass.getuser()))
                except FileExistsError:
                    pass
                log_file = os.path.abspath('/var/cache/raspiblitz/{}/blitz-tui.log'.format(getpass.getuser()))
            else:
                log_file = os.path.abspath(os.path.expanduser('~/blitz-tui.log'))

        default_config_as_dict = dict(
            version=1,
            disable_existing_loggers=False,
            formatters={'simple': {'format': '%(asctime)s - %(levelname)s - %(message)s'},
                        'extended': {
                            'format': '%(asctime)s - %(name)s - %(levelname)s - %(module)s:%(lineno)d - %(message)s'}},
            handlers={'console': {'class': 'logging.StreamHandler',
                                  'level': 'INFO',
                                  'formatter': 'extended',
                                  'stream': 'ext://sys.stdout'},
                      'file_handler': {'class': 'logging.handlers.RotatingFileHandler',
                                       'level': log_level,
                                       'formatter': 'extended',
                                       'filename': log_file,
                                       'maxBytes': 2*1024*1024,  # 2 MB
                                       'backupCount': 1,
                                       'encoding': 'utf8'}},
            loggers={'infoblitz': {'level': 'DEBUG',
                                   'handlers': ['console', 'file_handler'],
                                   'propagate': 'no'}},
            root={'level': 'DEBUG', 'handlers': ['console', 'file_handler']}
        )

        logging.config.dictConfig(default_config_as_dict)
