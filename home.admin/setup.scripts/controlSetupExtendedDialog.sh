#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info


source <(/home/admin/_cache.sh get ui_migration_upload ui_migration_uploadUnix ui_migration_uploadWin)
if [ "${ui_migration_upload}" = "1" ]; then

  sudo /home/admin/config.scripts/blitz.migration.sh import-gui

  /home/admin/_cache.sh set state "waitprovision"
  exit 0
fi

# break loop if no matching if above
/home/admin/_cache.sh set state "error"
exit 1