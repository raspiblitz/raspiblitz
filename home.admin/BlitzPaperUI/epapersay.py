# Command-line Usage: sudo python3 epapersay.py "Hello World"
import sys
sys.path.insert(1, "./drivers")

# there are two drivers, the epd2in7 and epd2in7b
# this script uses the monochrome epd2in7
# the other driver can be obtained from waveshare
# perhaps future developments will enable the 
# multi-color (black,white,red) epd2in7b display
import epd2in7
from PIL import Image, ImageDraw, ImageFont

def printToEPaperDisplay(string):

    epd = epd2in7.EPD()  # get the display
    epd.init()           # initialize the display
    epd.Clear(0xFF)      # clear the display
    print("epapersay.py: "+ string) # for debug purposes
    HBlackImage = Image.new('1', (epd2in7.EPD_HEIGHT, epd2in7.EPD_WIDTH), 255)
    # if we were using epd2in7b, we could also have HRedImage = Image.new('1', (epd2in7b.EPD_HEIGHT, epd2in7b.EPD_WIDTH), 255)
    
    draw = ImageDraw.Draw(HBlackImage) # Create draw object and pass in the image layer we want to work with (HBlackImage)
    #font = ImageFont.truetype('/usr/share/fonts/truetype/google/Bangers-Regular.ttf', 30) # Create our font, passing in the font file and font size
    
    draw.text((25, 65), string, fill = 0)
    
    epd.display(epd.getbuffer(HBlackImage)) # for epd2in7b, would need to include HRedImage as additional argument


# below lines allow us to use this file as either a module or a standalone script
def main():
    printToEPaperDisplay(sys.argv[1])


if __name__ == '__main__':
    main()
