#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys
import RPi.GPIO as GPIO

if len(sys.argv) <= 2 or sys.argv[1] in ["-h", "--help", "help"]:
    print ("# IMPORTANT: call with SUDO")
    print ("# read inputs on raspberryPi GPIO pins")
    print ("# blitz.gpio.py in [pinnumber]")
    print ("err='missing parameters'")
    sys.exit(1)

if sys.argv[2].isdigit() and int(sys.argv[2])>0 and int(sys.argv[2])<=40:
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(int(sys.argv[2]),GPIO.IN)
    print ("pinValue", end="=")
    print (GPIO.input(int(sys.argv[2])))
    GPIO.cleanup()
else:
    print ("err='not a valid pin number between 1 and 40'")
    sys.exit(1)