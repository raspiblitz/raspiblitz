import sys
sys.path.insert(1, "./drivers")

import epd2in7
from PIL import Image, ImageDraw, ImageFont

epd = epd2in7.EPD() # get the display
epd.init()           # initialize the display
print("Clearing e-paper display...")    # prints to console, not the display, for debugging
epd.Clear(0xFF)      # clear the display
print("Done.")
def printToDisplay(string):
    print("epaper-displaying: "+ string)
    HBlackImage = Image.new('1', (epd2in7.EPD_HEIGHT, epd2in7.EPD_WIDTH), 255)
    #HRedImage = Image.new('1', (epd2in7b.EPD_HEIGHT, epd2in7b.EPD_WIDTH), 255)
    
    draw = ImageDraw.Draw(HBlackImage) # Create draw object and pass in the image layer we want to work with (HBlackImage)
    #font = ImageFont.truetype('/usr/share/fonts/truetype/google/Bangers-Regular.ttf', 30) # Create our font, passing in the font file and font size
    
    draw.text((25, 65), string, fill = 0)
    
    epd.display(epd.getbuffer(HBlackImage))
    
printToDisplay("Hello, World!")
