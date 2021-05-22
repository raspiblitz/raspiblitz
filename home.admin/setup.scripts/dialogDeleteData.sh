#!/bin/bash

whiptail --title " FORMATTING DATA DRVE " --yes-button "DELETE DATA" --no-button "CANCEL" --yesno "For fresh setup your data drive needs to be formatted, but there is old data on your HDD/SSD that could contain funds.

Are you really sure that you want delete that old data?
      " 10 65

if [ "$?" == "0" ]; then
    # 0 --> delete data
    exit 0
else
    # 1 --> cancel
    exit 1
fi