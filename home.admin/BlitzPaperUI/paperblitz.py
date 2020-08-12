import epapersay

import time
from gpiozero import Button # for button control
from signal import pause # needed to block (for now) to wait for button press
import os
import sys

# Handle button presses
# param of type Button
def dispatchCommand(cmd):
    def handleBtnPress(btn):
        os.system(cmd)
    return handleBtnPress

def main():
    btn1 = Button(5)                              # assign each button to a variable
    btn2 = Button(6)                              # by passing in the pin number
    btn3 = Button(13)                             # associated with the button
    btn4 = Button(19)                             # 

    # tell the buttons what to do when pressed
    btn1.when_pressed = dispatchCommand(sys.argv[1])
    btn2.when_pressed = dispatchCommand(sys.argv[2])
    btn3.when_pressed = dispatchCommand(sys.argv[3])
    btn4.when_pressed = dispatchCommand(sys.argv[4])

    pause() # pause to wait for button press?

# below lines allow us to use this file as either a module or a standalone script
if __name__ == '__main__':
    main()

