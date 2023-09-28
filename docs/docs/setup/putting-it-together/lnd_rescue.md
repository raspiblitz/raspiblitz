---
sidebar_position: 4
---
# LNDRESCUE LND tar.gz-Backupfile (BEST)

Choose this option if you have made a complete backup of the LND or Core Lightning data and have a tar.gz file starting with the word 'lnd-rescue' or 'cl-rescue' available.
It will recover all your on-chain funds and open channels you had.
But you have to make sure that the rescue backup you have is really the latest version - otherwise you might lose channel funds.

_If you have tar.gz file that starts with 'raspiblitz', that's a migration file.
That also includes your old LND/Core Lightning wallet, but you import that file at the beginning of the setup process with 'FROMBACKUP - Upload Migration Backup' instead choosing FRESHSETUP_