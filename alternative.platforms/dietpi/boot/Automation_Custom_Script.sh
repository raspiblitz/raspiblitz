# Use this format to build the SDcard with the Raspiblitz script:  
# wget https://raw.githubusercontent.com/[GITHUB-USERNAME]/raspiblitz/[BRANCH]/build_sdcard.sh && sudo bash build_sdcard.sh [BRANCH] [GITHUB-USERNAME]`  
# If you are working from a forked repo be aware of that the fork needs to be called `raspiblitz` for the git downloads to work.

# Uncomment the line with the branch you want to build the SDcard from:

# @rootzoll v1.6 release branch:
wget https://raw.githubusercontent.com/rootzoll/raspiblitz/v1.6/build_sdcard.sh && sudo bash build_sdcard.sh

# @rootzoll dev branch:
# wget https://raw.githubusercontent.com/rootzoll/raspiblitz/dev/build_sdcard.sh && sudo bash build_sdcard.sh dev

# @openoms DietPi branch:
# wget https://raw.githubusercontent.com/openoms/raspiblitz/DietPi/build_sdcard.sh  && sudo bash build_sdcard.sh DietPi openoms