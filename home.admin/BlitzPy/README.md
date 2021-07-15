# BlitzPy

BlitzPy is a part of the RaspiBlitz project and implements a few common use cases.


## Installation

### Prerequisite

None

### Dependencies

None

### Install BlitzPy

```
cd ~/raspiblitz/home.admin/BlitzPy
pip install dist/BlitzPy-0.2.0-py2.py3-none-any.whl
OR
sudo -H python -m pip install dist/BlitzPy-0.2.0-py2.py3-none-any.whl
```

**or** consider using a virtual environment

```
python3 -m venv --system-site-packages venv
source venv/bin/activate
pip install BlitzPy
```

## Usage

### Import and use..

```
from blitzpy import RaspiBlitzConfig
cfg = RaspiBlitzConfig()
cfg.reload()
print(cfg.hostname.value)
if cfg.run_behind_tor.value:
    print("using Tor!")
```

### Changing values

In order to change the content of a setting the `value` attribute needs to be updated!

```
from blitzpy import RaspiBlitzConfig
cfg = RaspiBlitzConfig()
cfg.reload()
print(cfg.hostname.value)
cfg.hostname.value = "New-Hostname!"
print(cfg.hostname.value)
```

### Exporting

Use `cfg.write()` to export file (will use default path - override with cfg.write(path="/tmp/foobar.conf").

```
from blitzpy import RaspiBlitzConfig
cfg = RaspiBlitzConfig()
cfg.reload()
cfg.rtl_web_interface.value = True
cfg.write()
```

## License

[MIT License](http://en.wikipedia.org/wiki/MIT_License)
