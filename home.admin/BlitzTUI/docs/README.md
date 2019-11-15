# BlitzTUI Documentation (mainly for developers)

BlitzTUI is a part of the RaspiBlitz project and implements a Touch User Interface in PyQt5.

Make sure that PyQt5 is installed on the system

```
apt-get install python3-pyqt5
```


## Required tools

### for UI development

* QT Designer (GUI application for Linux, Mac and Windows)

### for compiling the .ui and .qrc files to python3

* pyuic5
* pyrcc5

`sudo apt-get install pyqt5-dev-tools`

### for building and uploading PyPI packages

* setuptools
* wheel
* twine

`python3 -m pip install --upgrade setuptools wheel twine`


## Mini-Tutorial

Have a look at the [Mini-Tutorial](tutorial.md)


## Release workflow

* `make build-ui` - in case there were any changes to the *.ui or *.qrc files
* make sure you have all changes added and commited (consider re-basing)
* update the version in `blitztui/version.py`
* update the `CHANGELOG.md` file (reflect the new version!)
* `git add CHANGELOG.md blitztui/version.py`
* `git commit` and set a proper commit message
* `make build`
* `make upload`


## Uploading to PyPI

Please use `twine` for uploading files to PyPI. You will need credentials for the BlitzTUI account.

```
$ cat ~/.pypirc
[distutils]
index-servers=
    pypi
    pypitest

[pypi]
username = RaspiBlitz
password = <REDACTED>

[pypitest]
repository = https://test.pypi.org/legacy/
username = RaspiBlitz-Test
password = <REDACTED>
```

## PRELOAD-What?!

**Update: This seems to be fixed since grpcio==1.24.3!**

What's the reason for this long `LD_PRELOAD` line?!

Apparently there is an incompatibility with the current version (as of writing this: **grpcio==1.24.1**) of
**gRPC** for Python on ARM (Raspberry Pi) that was released by Google. Running without `LD_PRELOAD` gives
an error regarding `undefined symbol: __atomic_exchange_8`:

```
(python3-env-lnd) admin@raspiblitz:~/raspiblitz/home.admin/BlitzTUI $ python3
Python 3.7.3 (default, Apr  3 2019, 05:39:12)
[GCC 8.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import grpc
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/admin/python3-env-lnd/lib/python3.7/site-packages/grpc/__init__.py", line 23, in <module>
    from grpc._cython import cygrpc as _cygrpc
ImportError: /home/admin/python3-env-lnd/lib/python3.7/site-packages/grpc/_cython/cygrpc.cpython-37m-arm-linux-gnueabihf.so: undefined symbol: __atomic_exchange_8
```

It is expected that this is resolved soon-ish.


## Directory tree

```
admin@raspiblitz:~/raspiblitz/home.admin/BlitzTUI $ tree
.
├── blitztui
│   ├── client.py
│   ├── config.py
│   ├── file_logger.py
│   ├── file_watcher.py
│   ├── __init__.py
│   ├── main.py
│   ├── memo.py
│   ├── ui
│   │   ├── home.py
│   │   ├── __init__.py
│   │   ├── invoice.py
│   │   ├── off.py
│   │   ├── qcode.py
│   │   └── resources_rc.py
│   └── version.py
├── CHANGELOG.md
├── data
│   ├── lnd.conf
│   ├── raspiblitz.conf
│   ├── raspiblitz.info
│   ├── Wordlist-Adjectives-Common-Audited-Len-3-6.txt
│   └── Wordlist-Nouns-Common-Audited-Len-3-6.txt
├── designer
│   ├── home.ui
│   ├── invoice.ui
│   ├── off.ui
│   └── qcode.ui
├── dist
├── docs
│   ├── images
│   │   └── QtDesigner.png
│   ├── README.md
│   └── tutorial.md
├── images
│   ├── blank_318x318.png
│   ├── Paid_Stamp.png
│   ├── RaspiBlitz_Logo_Berry.png
│   ├── RaspiBlitz_Logo_Condensed_270.png
│   ├── RaspiBlitz_Logo_Condensed_90.png
│   ├── RaspiBlitz_Logo_Condensed_Negative.png
│   ├── RaspiBlitz_Logo_Condensed.png
│   ├── RaspiBlitz_Logo_Icon_Negative.png
│   ├── RaspiBlitz_Logo_Icon.png
│   ├── RaspiBlitz_Logo_Main_270.png
│   ├── RaspiBlitz_Logo_Main_90.png
│   ├── RaspiBlitz_Logo_Main_Negative.png
│   ├── RaspiBlitz_Logo_Main.png
│   ├── RaspiBlitz_Logo_Stacked_270.png
│   ├── RaspiBlitz_Logo_Stacked_90.png
│   ├── RaspiBlitz_Logo_Stacked_Negative_270.png
│   ├── RaspiBlitz_Logo_Stacked_Negative_90.png
│   ├── RaspiBlitz_Logo_Stacked_Negative.png
│   └── RaspiBlitz_Logo_Stacked.png
├── LICENSE
├── make.cmd
├── Makefile
├── MANIFEST.in
├── README.md
├── requirements.txt
├── resources.qrc
├── setup.cfg
└── setup.py
```