#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 00infoLCDTK.py
#
# called by #
#   /home/pi/autostart.sh
# dev/test/run with:
#   sudo -i -u pi DISPLAY=:0.0 /usr/bin/python3 /home/admin/00infoLCDTK.py

import os
import sys
import json
import logging
import logging.config
import tkinter as tk

COLOR = "black"
WINFO = None

log = logging.getLogger()


def setup_logging(default_path='00infoLCDw.json'):
    """Setup logging configuration"""
    path = default_path
    if os.path.exists(path):
        with open(path, 'rt') as f:
            config = json.load(f)
        logging.config.dictConfig(config)
    else:  # if $default_path does not exist use the following default log setup
        default_config_as_json = """
{
    "version": 1,
    "disable_existing_loggers": false,
    "formatters": {
        "simple": {
            "format": "%(asctime)s - %(levelname)s - %(message)s"
        },
        "extended": {
            "format": "%(asctime)s - %(name)s - %(levelname)s - %(module)s:%(lineno)d - %(message)s"
        }

    },

    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "level": "INFO",
            "formatter": "simple",
            "stream": "ext://sys.stdout"
        },

        "file_handler": {
            "class": "logging.handlers.RotatingFileHandler",
            "level": "DEBUG",
            "formatter": "extended",
            "filename": "00infoLCDTK.log",
            "maxBytes": 10485760,
            "backupCount": 0,
            "encoding": "utf8"
        }
    },

    "loggers": {
        "infoblitz": {
            "level": "INFO",
            "handlers": ["console", "file_handler"],
            "propagate": "no"
        }
    },

    "root": {
        "level": "INFO",
        "handlers": ["console", "file_handler"]
    }
}
"""
        config = json.loads(default_config_as_json)
        logging.config.dictConfig(config)


def callback_b1():
    global WINFO
    log.info("clicked b1 - Donations")
    if sys.platform != "win32":
        os.system("xterm -fn fixed -into %d +sb -hold /home/admin/XXbutton1.sh &" % WINFO)

def callback_b2():
    global WINFO
    log.info("clicked b2 - no action yet (placeholder)")
    #if sys.platform != "win32":
    #    os.system("xterm -fn fixed -into %d +sb -hold /home/admin/XXbutton2.sh &" % WINFO)

def callback_b3():
    global WINFO
    log.info("clicked b3 - no action yet")
    #if sys.platform != "win32":
    #    os.system("xterm -fn fixed -into %d +sb -hold /home/admin/XXbutton3.sh &" % WINFO)

def callback_b4():
    global WINFO
    log.info("clicked b4")
    if sys.platform != "win32":
        os.system("xterm -fn fixed -into %d +sb -hold /home/admin/XXshutdown.sh &" % WINFO)


def main():
    global WINFO
    setup_logging()
    log.info("Starting 00infoLCDTK.py")

    # LCD root
    root = tk.Tk()
    root.config(bg=COLOR)
    root.overrideredirect(1)
    root.geometry("480x320+0+0")
    root.title("RaspiBlitz")

    # but LCD on canvas
    entry = tk.Entry(root)
    entry.config(bg=COLOR, highlightbackground=COLOR)
    entry.pack(side="bottom", fill="x")

    # button frame
    frame1 = tk.Frame(entry, width=80, background="black")
    frame1.pack(side="left", fill="both", expand=True)

    # button 1 - Donations
    button1 = tk.Button(frame1, text=r'Donations', fg='black', command=callback_b1, wraplength=1, height = 10, width = 1)
    button1.pack(pady=24)

    # button 2 - no action yet (placeholder)
    #button2 = tk.Button(frame1, text='\u002d', fg='black', command=callback_b2, height = 1, width = 1)
    #button2.pack(pady=24)

    # button 3 - no action yet (placeholder)
    #button3 = tk.Button(frame1, text='\u002d', fg='black', command=callback_b3, height = 1, width = 1)
    #button3.pack(pady=24)
    #label3 = tk.Label(frame1, text='1.3', bg=COLOR, fg='white')
    #label3.pack(pady=24)

    # button 4 - no action yet (power down)
    button4 = tk.Button(frame1,  text='\N{BLACK CIRCLE}', fg='red', command=callback_b4, height = 1, width = 1)
    button4.pack(pady=24)

    # content frame
    frame2 = tk.Frame(entry, width=400, background="grey")
    frame2.pack(side="right", fill="both", expand=True)

    # run terminal in
    WINFO = frame2.winfo_id()
    if sys.platform != "win32":
        os.system("xterm -fn fixed -into %d +sb -hold /home/admin/00infoLCD.sh &" % WINFO)

    # run
    root.mainloop()


if __name__ == '__main__':
    main()
