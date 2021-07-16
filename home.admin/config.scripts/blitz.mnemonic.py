#!/usr/bin/python3

from mnemonic import Mnemonic

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