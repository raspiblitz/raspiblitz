#!/usr/bin/env python3

# usage:
# python3 tor.newnym.py [ControlPort] # 9051|9071

from stem import Signal
from stem.control import Controller

var_port = sys.argv[1]
print(var_port)

with Controller.from_port(port = var_port) as controller:
  controller.authenticate()
  controller.signal(Signal.NEWNYM)

# with Controller.from_port(port = 9051) as controller:
#   controller.authenticate()
#   controller.signal(Signal.NEWNYM)
