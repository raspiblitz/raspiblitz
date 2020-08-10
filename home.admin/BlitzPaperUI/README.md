## BlitzPaperUI
This implements a simple user interface for the Raspiblitz using a waveshare e-paper HAT.

### Hardware
Right now the e-paper display we use is the [2.7-inch Waveshare](https://www.waveshare.com/wiki/2.7inch_e-Paper_HAT)
which conveniently has 4 buttons on one side.

### Usage/Examples
Will attempt to keep these examples updated to reflect the current state of the library.

Printing a message to the screen.
* `sudo python3 epapersay.py "Reckless Raspiblitz!!"` 

### Next Development Goal
* Print a message when one of the 4 buttons is pressed.

### Achieved Development Goals
* Done - able to print a message to the epaper-display (`epapersay.py`)

### Backlog
1. Display a more useful Raspiblitz-specific status message on the display
2. Display a Raspiblitz-specific thing  when button is pressed (perhaps a lightning invoice?)
3. Run the epaper display as a service?
4. Revisit PaperTTY and decide whether to use it or just go from scratch.

### Helpful Guides/Libraries
* [This Blog Article](https://dev.to/ranewallin/getting-started-with-the-waveshare-2-7-epaper-hat-on-raspberry-pi-41m8)
* [The PaperTTY Library](https://github.com/joukos/PaperTTY) might be useful 
