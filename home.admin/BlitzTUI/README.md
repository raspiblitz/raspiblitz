# BlitzTUI

[![VersionBadge](https://badge.fury.io/py/BlitzTUI.svg)](https://badge.fury.io/)
[![LicenseBadge](https://img.shields.io/badge/license-MIT-blue.svg)](https://shields.io/)
[![PythonVersions](https://img.shields.io/badge/python-3.4%2C%203.5%2C%203.6%2C%203.7%2C%203.8-blue.svg)](https://shields.io/)

BlitzTUI is a part of the RaspiBlitz project and implements a Touch User Interface in PyQt5.

## Installation


### Prerequisite

QT is needed. Please install PyQt5 (see below).


### Dependencies

#### Debian/Ubuntu (and similar)

```
apt-get install python3-pyqt5
```

#### PIP

The PIP dependencies are installed automatically - this listing is "FYI"

* grpcio
* googleapis-common-protos
* inotify
* psutil
* pyqtspinner
* qrcode


### Install BlitzTUI

```
pip install BlitzTUI
```

**or** consider using a virtual environment

```
virtualenv -p python3 --system-site-packages venv
source venv/bin/activate
pip install BlitzTUI
```


## Error Messages

For now the following warning/error/info messages can be ignored. If anybody knows how to suppress
or fix them please send a PR (or open an issue).

```
libEGL warning: DRI2: failed to authenticate
QStandardPaths: XDG_RUNTIME_DIR not set, defaulting to '/tmp/runtime-pi'
2019-11-02 20:01:21,504 - root - INFO - main:214 - /usr/bin/xterm: cannot load font "-Misc-Fixed-medium-R-*-*-13-120-75-75-C-120-ISO10646-1"
```

## License

[MIT License](http://en.wikipedia.org/wiki/MIT_License)
