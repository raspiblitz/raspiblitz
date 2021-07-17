#!/usr/bin/python3

import sys
from mnemonic import Mnemonic

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("tool for seed words")
    print("blitz.mnemonic.py generate")
    print("blitz.mnemonic.py test \"[SEEDWORDS-SPACE-SEPERATED]\"")
    sys.exit(1)

#######################
# GENERATE SEED WORDS
#######################
def generate():

    mnemo = Mnemonic("english")
    seedwords = mnemo.generate(strength=256)

    print("seedwords='" + seedwords + "'")

    # add a 6x4 formatted version to the output
    wordlist = list(seedwords.split(" "))
    seed_words_6x4 = ""
    for i in range(0, len(wordlist)):
        if i % 6 == 0 and i != 0:
            seed_words_6x4 = seed_words_6x4 + "\n"
        single_word = str(i + 1) + ":" + wordlist[i]
        while len(single_word) < 12:
            single_word = single_word + " "
        seed_words_6x4 = seed_words_6x4 + single_word
    print("seedwords6x4='" + seed_words_6x4 + "'")


#######################
# TEST SEED WORDS
#######################
def test(words):

    mnemo = Mnemonic("english")
    seed = mnemo.to_seed(words, passphrase="")
    print(vars(seed))

def main():
    if sys.argv[1] == "generate":
        generate()

    elif sys.argv[1] == "test":
        test(sys.argv[2])

    else:
        # UNKNOWN PARAMETER
        print("error='unknown parameter'")

if __name__ == '__main__':
    main()