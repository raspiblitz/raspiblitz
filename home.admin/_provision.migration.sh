#!/bin/bash

# check if run by root user
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

# LOGFILE - store debug logs of bootstrap
logFile="/home/admin/raspiblitz.log"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"
source ${infoFile}

# SETUPFILE - data from setup process
source /var/cache/raspiblitz/temp/raspiblitz.setup

# CACHEDATA - import needed data from cache 
source <(/home/admin/_cache.sh get hddGotMigrationData hddVersionLND)

# log header
echo "###################################" >> ${logFile}
echo "# _provision.migration.sh" >> ${logFile}
echo "###################################" >> ${logFile}
/home/admin/_cache.sh set message "Provision Migration"

if [ "${hddGotMigrationData}" == "" ]; then
  /home/admin/config.scripts/blitz.error.sh _provision.migration.sh "missing-migrationdata" "missing hddGotMigrationData" "" ${logFile}
  exit 2
fi

err=""
nodenameUpperCase=$(echo "${hddGotMigrationData}" | tr "[a-z]" "[A-Z]")
echo "**************************************************" >> ${logFile}
echo "MIGRATION FROM ${nodenameUpperCase} TO RASPIBLITZ" >> ${logFile}
echo "**************************************************" >> ${logFile}
echo "- started ..." >> ${logFile}
/home/admin/config.scripts/blitz.migration.sh migration-${hddGotMigrationData} >> ${logFile}
if [ "$?" != "0" ]; then
    /home/admin/config.scripts/blitz.error.sh _provision.migration.sh "migration-failed" "see provision migration logs" "Recover funds with fresh sd card using seed words + static channel backup." ${logFile}
    exit 3
fi

# make sure a raspiblitz.conf exists after migration
confExists=$(ls /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null | grep -c "raspiblitz.conf")
if [ "${confExists}" != "1" ]; then
    /home/admin/config.scripts/blitz.error.sh _provision.migration.sh "missing-config" "no /mnt/hdd/app-data/raspiblitz.conf" "After runningn migration process - no raspiblitz.conf abvailable." ${logFile}
    exit 6
fi

# make sure for the rest of the setup info is set correctly
/home/admin/config.scripts/blitz.conf.sh set network "bitcoin"
/home/admin/config.scripts/blitz.conf.sh set chain "main"
echo "Provisioning ${network} Mainnet - run config script" >> ${logFile}
/home/admin/config.scripts/bitcoin.install.sh on mainnet >> ${logFile} 2>&1

# set Password B
echo "## SETTING PASSWORD B" >> ${logFile}
if [ "${setPasswordB}" == "1" ]; then
 if [ "${passwordB}" != "" ]; then
    # set password B as RPC password
    echo "# setting PASSWORD B" >> ${logFile}
    /home/admin/config.scripts/blitz.passwords.sh set b "${passwordB}" >> ${logFile}
 else
    /home/admin/config.scripts/blitz.error.sh _provision.migration.sh "missing-passwordb" "FAIL: Password B should be set but was empty! Running with default." "" ${logFile}
    exit 4
 fi
else
  /home/admin/config.scripts/blitz.error.sh _provision.migration.sh "missing-setpasswordb" "setPasswordB!=1 this not normal on migration! Running with default." "" ${logFile}
  exit 5
fi

# if free space is lower than 100GB (100000000) delete backup files
if [ "${hddDataFreeKB}" != "" ] && [ ${hddDataFreeKB} -lt 407051412 ]; then
    echo "- free space of data disk is low ... deleting 'backup_migration'" >> ${logFile}
    rm -R /mnt/hdd/backup_migration
else
    echo "- old data of ${nodenameUpperCase} can be found in '/mnt/hdd/backup_migration'" >> ${logFile}
fi
echo "OK MIGRATION" >> ${logFile}
echo "END Migration"  >> ${logFile}
exit 0