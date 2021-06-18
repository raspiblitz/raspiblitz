import os
import time
import sys

if (len(sys.argv) != 3):
    print()
    print("Play text art animations in the terminal\n")
    print("Usage: python3 text_art.py <folder> <loops>")
    print("\t<folder>\tFolder containing text art frames")
    print("\t<loops>\t\tNumber of times to loop the animation or use -1 to loop until the user terminates the program")
    print()
    sys.exit(0)

folder_name = sys.argv[1]
loops = int(sys.argv[2])

if not os.path.isdir(folder_name):
    print(folder_name + " could not be found")
    sys.exit(0)

files_exist = True
num_found = 0

text_files = []

while files_exist:
    file_name = folder_name + "/" + str(num_found) + ".txt"
    
    if os.path.isfile(file_name):
        f = open(file_name, "r")
        text_files.append(f.read())
        num_found += 1
    else:
        files_exist = False

if len(text_files) == 0:
    print(folder_name + " did not have text art files")
    sys.exit(0)

i = 0
first = True
backspace_adjust = (len(text_files[0].split("\n")) + 1) * "\033[A"

while i < loops or loops == -1:
    for text_file in text_files:

        if not first:
            print(backspace_adjust)
        
        print(text_file)
        
        first = False
        time.sleep(.05)
        
    i += 1
