#!/bin/bash

# A solid hardware setup is important to garantuee stability of data
# This script checks the hardware and gives user feedback.

# Start with parameter "no-new-stresstest" to just use the already
# made stresstest report during boostrap script. 

# INFOFILE - state data from bootstrap
source /home/admin/raspiblitz.info

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
    echo "TODO: show power FAIL info: ${powerMIN}"
  else
    echo "TODO: show power WARN info: ${powerMIN}"
  fi
fi

if [ ${#undervoltageReports} -gt 0 ]; then
  if [ ${undervoltageReports} -gt 0 ]; then
    showPowerImproveInfo=1
    echo "TODO: show Undervoltage Info info: ${undervoltageReports}"
  fi
fi

if [ ${showPowerImproveInfo} -gt 0 ]; then
    echo "TODO: Tell user how to improve Power"
    # tell users if they have a power supply from the shopping list, they should report in
fi

# check for heat issues
showHeatImproveInfo=0
if [ ${tempWARN} -gt 0 ]; then
  showHeatImproveInfo=1
  if [ ${tempFAIL} -gt 0 ]; then
    echo "TODO: show heat FAIL info: ${heatMAX}"
  else
    echo "TODO: show heat WARN info: ${heatMAX}"
  fi
fi

if [ ${showHeatImproveInfo} -gt 0 ]; then
    echo "TODO: Tell user how to improve Heat"
fi

if [ ${showPowerImproveInfo} -eq 0 ] && [ ${showHeatImproveInfo} -eq 0 ]; then
    echo "TODO: Tell user everything is OK"
fi