import epapersay

import time
from gpiozero import Button # for button control
from signal import pause # needed to block (for now) to wait for button press


# Handle button presses
# param of type Button
def handleBtnPress(btn):
    epapersay.printToEPaperDisplay("Button pressed, pin = {}".format(btn.pin.number))

def main():
    btn1 = Button(5)                              # assign each button to a variable
    btn2 = Button(6)                              # by passing in the pin number
    btn3 = Button(13)                             # associated with the button
    btn4 = Button(19)                             # 

    # tell the buttons what to do when pressed
    btn1.when_pressed = handleBtnPress
    btn2.when_pressed = handleBtnPress
    btn3.when_pressed = handleBtnPress
    btn4.when_pressed = handleBtnPress

    pause() # pause to wait for button press?

# below lines allow us to use this file as either a module or a standalone script
if __name__ == '__main__':
    main()

