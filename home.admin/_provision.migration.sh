#!/bin/bash

# LOGFILE - store debug logs of bootstrap
logFile="/home/admin/raspiblitz.provision-migration.log"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"
source ${infoFile}

# SETUPFILE - data from setup process
source /var/cache/raspiblitz/temp/raspiblitz.setup

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# log header
echo "" > ${logFile}
echo "###################################" >> ${logFile}
echo "# _provision.migration.sh" >> ${logFile}
echo "###################################" >> ${logFile}
sudo sed -i "s/^message=.*/message='Provision Migration'/g" ${infoFile}

if [ "${hddGotMigrationData}" == "" ]; then
  sed -i "s/^state=.*/state=error/g" ${infoFile}
  sed -i "s/^message=.*/message='config: missing hddGotMigrationData'/g" ${infoFile}
  echo "FAIL see ${logFile}"
  echo "FAIL: missing hddGotMigrationData in (${infoFile})!" >> ${logFile}
  exit 2
fi

source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)

err=""
nodenameUpperCase=$(echo "${hddGotMigrationData}" | tr "[a-z]" "[A-Z]")
echo "**************************************************" >> ${logFile}
echo "MIGRATION FROM ${nodenameUpperCase} TO RASPIBLITZ" >> ${logFile}
echo "**************************************************" >> ${logFile}
echo "- started ..." >> ${logFile}
source <(sudo /home/admin/config.scripts/blitz.migration.sh migration-${hddGotMigrationData})
if [ "${err}" != "" ]; then
    echo "MIGRATION FAILED: ${err}" >> ${logFile}
    echo "Format data disk on laptop & recover funds with fresh sd card using seed words + static channel backup." >> ${logFile}
    sed -i "s/^state=.*/state=error/g" ${infoFile}
    sed -i "s/^message=.*/message='migration failed'/g" ${infoFile}
    exit 3
fi

# make sure for the rest of the seup info is set correctly
sudo sed -i "s/^network=.*/network=bitcoin/g" ${infoFile}
sudo sed -i "s/^chain=.*/chain=main/g" ${infoFile}

# set Password B
echo "## SETTING PASSWORD B" >> ${logFile}
if [ "${setPasswordB}" == "1" ]; then
 if [ "${passwordB}" != "" ]; then
    # set password B as RPC password
    echo "# setting PASSWORD B" >> ${logFile}
    /home/admin/config.scripts/blitz.setpassword.sh b "${passwordB}" >> ${logFile}
 else
    echo "FAIL: Password B should be set but was empty! Running with default." >> ${logFile}
 fi
else
  echo "WARN: setPasswordB!=1 this not normal on migration! Running with default." >> ${logFile}
fi

# if free space is lower than 100GB (100000000) delete backup files
if [ "${hddDataFreeKB}" != "" ] && [ ${hddDataFreeKB} -lt 407051412 ]; then
    echo "- free space of data disk is low ... deleting 'backup_migration'" >> ${logFile}
    sudo rm -R /mnt/hdd/backup_migration
else
    echo "- old data of ${nodenameUpperCase} can be found in '/mnt/hdd/backup_migration'" >> ${logFile}
fi
echo "OK MIGRATION" >> ${logFile}
echo "END Migration"  >> ${logFile}
exit 0

