#!/bin/bash

# A solid hardware setup is important to garantuee stability of data
# This script checks the hardware and gives user feedback.

# Start with parameter "no-new-stresstest" to just use the already
# made stresstest report during boostrap script. 

# INFOFILE - state data from bootstrap
source /home/admin/raspiblitz.info
source /home/admin/_version.info

clear
echo "*** Hardware Test Report ***"
echo ""

# check for parameter
parameter="$1"

if [ "${parameter}" != "no-new-stresstest" ]; then
  sudo /home/admin/config.scripts/blitz.stresstest.sh /home/admin/stresstest.report
  echo ""
fi

# load the stresstest values
source /home/admin/stresstest.report

#########################
# Explain Report to User
#########################

# check for power issues
showPowerImproveInfo=0
if [ ${powerWARN} -gt 0 ]; then
  showPowerImproveInfo=1
  if [ ${powerFAIL} -gt 0 ]; then
    whiptail --backtitle "RaspiBlitz v${codeVersion} - ${powerMIN}" --title " POWER SUPPLY CRITICAL " --msgbox "
Your power supply was FAILING the stress test (${powerMIN}).
Most reports of data loss are caused by weak power supplies.
Also a lot of RaspiBlitz setups fail because of weak power supplies.
To SHUTDOWN and upgrade the Power Supply is HIGHLY RECOMMENDED.

See upcomming screen on detailed info how to improve on power supply.

" 14 78
  else
    whiptail --backtitle "RaspiBlitz v${codeVersion} - ${powerMIN}" --title " Power Supply Warning " --msgbox "
Your power supply seems OK - but could be better for stable operations.
A replacement/upgrade of the Power Supply is recommended if possible.
Because most reports of data loss are caused by weak power supplies.

See upcomming screen on detailed info how to improve on power supply.

" 12 78
  fi
fi

if [ ${#undervoltageReports} -gt 0 ]; then
  if [ ${undervoltageReports} -gt 0 ]; then
    showPowerImproveInfo=1
    whiptail --backtitle "RaspiBlitz v${codeVersion}" --title " Runtime Undervoltages Detected " --msgbox "
Already during runtime of RaspiBlitz Undervoltage Reports were detected.
A upgrade of the Power Supply is strongly recommended (see next screen).

You should see the number of outages on your LCD as an ongoing counting.
Note that after replacement of power supply this number is not set to 0. 
As long that counting is not going further up you are good.

" 13 78
  fi
fi

if [ ${showPowerImproveInfo} -gt 0 ]; then

    whiptail --backtitle "RaspiBlitz v${codeVersion}" --title " What todo on Power Issues " --msgbox "
To improve on power issues an upgrade of the power supply is recommended.
Check if you have the latest power supply listed in your shopping list.
If you have that one, please report on GitHub that alternative is needed.

In general a good power supply needs to fullfill this three points:
- needs to deliver at least 3 Ampere
- needs to deliver a stable >=5V output (big & clunky is good)
- needs a thick cable (low AWG score) & best is no switch

If you think all is good with your power supply please also re-run test
up to 3 times. Sometimes a good power supply has 1 or 2 bad measurements. 

" 18 78

    choice=$(whiptail --backtitle "RaspiBlitz v${codeVersion}" --title " Hardware Check " --menu "What todo about Power Issues?" 12 60 6 \
TESTAGAIN "Run Test again to be sure." \
CONTINUE "I take the risk - continue." \
SHUTDOWN "Shutdown to change hardware." 3>&1 1>&2 2>&3)
    if [ ${#choice} -eq 0 ]; then
      choice="CONTINUE"
    fi
    if [ "${choice}" == "TESTAGAIN" ]; then
      echo "Shutting down ..."
      sudo /home/admin/05hardwareTest.sh
      exit 0
    elif [ "${choice}" == "SHUTDOWN" ]; then
      echo "Shutting down ..."
      sudo shutdown now
      exit 1
    else
      echo "OK continue .."
    fi
fi

# check for heat issues
showHeatImproveInfo=0
if [ ${tempWARN} -gt 0 ]; then
  showHeatImproveInfo=1
  if [ ${tempFAIL} -gt 0 ]; then
    whiptail --backtitle "RaspiBlitz v${codeVersion} - ${tempMAX}" --title " HEAT MANAGEMENT CRITICAL " --msgbox "
Your RaspiBlitz is getting MUCH TOO HOT (${tempMAX}).
The system is getting very slow when hot - thats not a NO GO but bad.
An upgrade of the Heat Management is HIGHLY RECOMMENDED.

See upcomming screen on detailed info how to improve heat management.

" 12 78
  else
    whiptail --backtitle "RaspiBlitz v${codeVersion} - ${tempMAX}" --title " Heat Management Warning " --msgbox "
Your RaspiBlitz is getting a bit too hot (${tempMAX}).
The system is getting slow when hot - thats not a NO GO but bad.
An upgrade of the Heat Management is recommended if possible.

See upcomming screen on detailed info how to improve heat management.

" 12 78
  fi
fi

if [ ${showHeatImproveInfo} -gt 0 ]; then
 
    whiptail --backtitle "RaspiBlitz v${codeVersion}" --title " What todo on Heat Issues " --msgbox "
To improve on heat issues an upgrade of the casing is recommended.
Check if you have the latest casing options in your shopping list.
Use a big passive heat sink or fan to prevent overheating.
If you have already one, check if its applied correctly to CPU.
In extreme cases consider some external fan helping out.

Again a RaspiBlitz getting hot can be tolerated. But it is
slowing down your CPU and may reduce the lifetime of hardware. 

" 16 72

    choice=$(whiptail --backtitle "RaspiBlitz v${codeVersion}" --title " Hardware Check " --menu "What todo about Heat Issues?" 12 60 6 \
TESTAGAIN "Run Test again to be sure." \
CONTINUE "I take the risk - continue." \
SHUTDOWN "Shutdown to change hardware." 3>&1 1>&2 2>&3)
    if [ ${#choice} -eq 0 ]; then
      choice="CONTINUE"
    fi
    if [ "${choice}" == "TESTAGAIN" ]; then
      echo "Shutting down ..."
      sudo /home/admin/05hardwareTest.sh
      exit 0
    elif [ "${choice}" == "SHUTDOWN" ]; then
      echo "Shutting down ..."
      sudo shutdown now
      exit 1
    else
      echo "OK continue .."
    fi

fi

if [ ${showPowerImproveInfo} -eq 0 ] && [ ${showHeatImproveInfo} -eq 0 ]; then
          dialog --backtitle "RaspiBlitz v${codeVersion}" --title " Hardware Check " --msgbox "
RaspiBlitz hardware setup looks good :)
You are ready to continue - have fun.

" 8 43
fi
