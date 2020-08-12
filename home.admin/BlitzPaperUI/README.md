## BlitzPaperUI
This implements a simple user interface for the Raspiblitz using a waveshare e-paper HAT.

### Hardware
Right now the e-paper display we use is the [2.7-inch Waveshare](https://www.waveshare.com/wiki/2.7inch_e-Paper_HAT)
which conveniently has 4 buttons on one side.

### Design
The initial goal of the functionality in this set of scripts/programs is to find the balance between
simplicity and generality. As such, we break the functionality of the e-paper design into components
and develop simple utility programs to interact with the components. Functionality, at least initially,
is quite limited to:
1. displaying something on the e-paper display
2. doing something when one of the 4 buttons is pressed

By exposing both of the above via a simple command-line interface, the hope is that apps on higher layers,
or even Raspiblitz owners/users directly, can very easily interact with or otherwise customize the setup.

### Usage/Examples
Right now the scripts available are extremely simple/minimal and probably full of a lot of bugs, uncaught
corner cases, etc. Nevertheless, we will attempt to keep these examples updated to reflect the current 
state of the library.

* Printing a message to the screen: `sudo python3 epapersay.py "Reckless Raspiblitz!!"`
* Reacting to button press: `sudo python3 paperblitz.py "echo 1" "echo 2" "echo 3" "sudo python3 epapersay.py \"hello\""` 
  will run the `echo i` commands for buttons 1-3, and for button 4 will
  print to the display itself using `papersay.py`. Naturally any of these arguments could be replaced by
  arbitrary commands.

### Next Development Goal
* Refactor button code

### Achieved Development Goals
* Done -  A command like `paperblitz.py <str0> <str1> <str2> <str3> <str4>` should display `<str0>` on the blitz
  and replace it with `<strN>` when button `N` is pressed.
* Done - Print a message when one of the 4 buttons is pressed.
* Done - able to print a message to the epaper-display (`epapersay.py`)

### Backlog
1. Display a more useful Raspiblitz-specific status message on the display
2. Display a Raspiblitz-specific thing  when button is pressed (perhaps a lightning invoice?)
3. Run the epaper display as a service?
4. Revisit PaperTTY and decide whether to use it or just go from scratch.

### Helpful Guides/Libraries
* [This Blog Article](https://dev.to/ranewallin/getting-started-with-the-waveshare-2-7-epaper-hat-on-raspberry-pi-41m8)
* [The PaperTTY Library](https://github.com/joukos/PaperTTY) might be useful 
