#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to set a passwords A,B,C & D"
 echo "blitz.setpassword.sh [?a|b|c|d] [?newpassword] "
 echo "or just as a password enter dialog (result as file)"
 echo "blitz.setpassword.sh [x] [text] [result-file]"
 echo "exits on 0 = needs reboot"
 exit 1
fi

# check if sudo
if [ "$EUID" -ne 0 ]
  then echo "Please run as root (with sudo)"
  exit
fi

# tempfile 
_temp="./dialog.$$"

# load raspiblitz config (if available)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then
  network="bitcoin"
fi
if [ ${#chain} -eq 0 ]; then
  chain="main"
fi

# 1. parameter [?a|b|c|d]
abcd=$1

# 2. parameter [?newpassword]
newPassword=$2

# run interactive if no further parameters
OPTIONS=()
if [ ${#abcd} -eq 0 ]; then
    OPTIONS+=(A "Master User Password / SSH")
    OPTIONS+=(B "RPC Password (blockchain/lnd)")
    OPTIONS+=(C "LND Wallet Password")
    OPTIONS+=(D "LND Seed Password")
    CHOICE=$(dialog --clear \
                --backtitle "RaspiBlitz" \
                --title "Set Password" \
                --menu "Which password to change?" \
                11 50 7 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
    clear
    case $CHOICE in
        A)
          abcd='a';
          ;;
        B)
          abcd='b';
          ;;
        C)
          abcd='c';
          ;;
        D)
          abcd='d';
          ;;
        *)
          exit 1
          ;;
    esac
fi

echo "Changing Password ${abcd} ..."
echo ""

############################
# PASSWORD A
if [ "${abcd}" = "a" ]; then

  # if no password given by parameter - ask by dialog
  if [ ${#newPassword} -eq 0 ]; then

    # ask user for new password A (first time)
    dialog --backtitle "RaspiBlitz - Setup"\
       --insecure --passwordbox "Set new Master/Admin Password A:\n(min 8chars, 1word, chars+number, no specials)" 10 52 2>$_temp

    # get user input
    password1=$( cat $_temp )
    shred $_temp

    # ask user for new password A (second time)
    dialog --backtitle "RaspiBlitz - Setup"\
       --insecure --passwordbox "Re-Enter Password A:\n(This is new password to login per SSH)" 10 52 2>$_temp

    # get user input
    password2=$( cat $_temp )
    shred $_temp

    # check if passwords match
    if [ "${password1}" != "${password2}" ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Passwords dont Match\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh a
      exit 1
    fi

    # password zero
    if [ ${#password1} -eq 0 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Password cannot be empty\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh a
      exit 1
    fi

    # check that password does not contain bad characters
    clearedResult=$(echo "${password1}" | tr -dc '[:alnum:]-.' | tr -d ' ')
    if [ ${#clearedResult} != ${#password1} ] || [ ${#clearedResult} -eq 0 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Contains bad characters (spaces, special chars)\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh a
      exit 1
    fi

    # password longer than 8
    if [ ${#password1} -lt 8 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Password length under 8\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh a
      exit 1
    fi

    # use entred password now as parameter
    newPassword="${password1}"

  fi  

  # change user passwords and then change hostname
  echo "pi:$newPassword" | sudo chpasswd
  echo "root:$newPassword" | sudo chpasswd
  echo "bitcoin:$newPassword" | sudo chpasswd
  echo "admin:$newPassword" | sudo chpasswd
  sleep 1

  echo ""
  echo "OK - password A changed for user pi, root, admin & bitcoin"
  exit 0

############################
# PASSWORD B
elif [ "${abcd}" = "b" ]; then

  # if no password given by parameter - ask by dialog
  if [ ${#newPassword} -eq 0 ]; then
    # ask user for new password A (first time)
    dialog --backtitle "RaspiBlitz - Setup"\
       --insecure --passwordbox "Please enter your RPC Password B:\n(min 8chars, 1word, chars+number, no specials)" 10 52 2>$_temp

    # get user input
    password1=$( cat $_temp )
    shred $_temp

    # ask user for new password A (second time)
    dialog --backtitle "RaspiBlitz - Setup"\
       --insecure --passwordbox "Re-Enter Password B:\n" 10 52 2>$_temp

    # get user input
    password2=$( cat $_temp )
    shred $_temp

    # check if passwords match
    if [ "${password1}" != "${password2}" ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Passwords dont Match\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh b
      exit 1
    fi

    # password zero
    if [ ${#password1} -eq 0 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Password cannot be empty\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh b
      exit 1
    fi

    # check that password does not contain bad characters
    clearedResult=$(echo "${password1}" | tr -dc '[:alnum:]-.' | tr -d ' ')
    if [ ${#clearedResult} != ${#password1} ] || [ ${#clearedResult} -eq 0 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Contains bad characters (spaces, special chars)\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh b
      exit 1
    fi

    # password longer than 8
    if [ ${#password1} -lt 8 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Password length under 8\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh b
      exit 1
    fi

    # use entred password now as parameter
    newPassword="${password1}"
  fi

  # change in assets (just in case this is used on setup)
  sed -i "s/^rpcpassword=.*/rpcpassword=${newPassword}/g" /home/admin/assets/${network}.conf 2>/dev/null
  sed -i "s/^${network}d.rpcpass=.*/${network}d.rpcpass=${newPassword}/g" /home/admin/assets/lnd.${network}.conf 2>/dev/null

  # change in real configs
  sed -i "s/^rpcpassword=.*/rpcpassword=${newPassword}/g" /mnt/hdd/${network}/${network}.conf 2>/dev/null
  sed -i "s/^rpcpassword=.*/rpcpassword=${newPassword}/g" /home/admin/.${network}/${network}.conf 2>/dev/null
  sed -i "s/^${network}d.rpcpass=.*/${network}d.rpcpass=${newPassword}/g" /mnt/hdd/lnd/lnd.conf 2>/dev/null
  sed -i "s/^${network}d.rpcpass=.*/${network}d.rpcpass=${newPassword}/g" /home/admin/.lnd/lnd.conf 2>/dev/null
  
  # RTL - keep settings from current RTL-Config.json
  if [ "${rtlWebinterface}" == "on" ]; then
    echo "# changing RTL password"
    cp /home/admin/RTL/RTL-Config.json /home/admin/RTL/backup-RTL-Config.json
    # remove hashed old password
    #sed -i "/\b\(multiPassHashed\)\b/d" ./RTL-Config.json
    # set new password
    chmod 600 /home/admin/RTL/RTL-Config.json || exit 1
    node > /home/admin/RTL/RTL-Config.json <<EOF
//Read data
var data = require('/home/admin/RTL/backup-RTL-Config.json');
//Manipulate data
data.multiPassHashed = null;
data.multiPass = '$newPassword';
//Output data
console.log(JSON.stringify(data, null, 2));
EOF
    rm -f /home/admin/RTL/backup-RTL-Config.json
  fi
  
  # electrs
  if [ "${ElectRS}" == "on" ]; then
    echo "# changing ELECTRS password"
    RPC_USER=$(cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
    sed -i "s/^cookie = \"$RPC_USER.*\"/cookie = \"$RPC_USER:${newPassword}\"/g" /home/electrs/.electrs/config.toml 2>/dev/null
  fi

  # BTC-RPC-Explorer
  if [ "${BTCRPCexplorer}" = "on" ]; then
    echo "# changing BTCRPCEXPLORER password"
    sed -i "s/^BTCEXP_BITCOIND_URI=$network:\/\/$RPC_USER:.*@127.0.0.1:8332?timeout=10000/BTCEXP_BITCOIND_URI=$network:\/\/$RPC_USER:${newPassword}@127.0.0.1:8332\?timeout=10000/g" /home/bitcoin/.config/btc-rpc-explorer.env 2>/dev/null
    sed -i "s/^BTCEXP_BITCOIND_PASS=.*/BTCEXP_BITCOIND_PASS=${newPassword}/g" /home/bitcoin/.config/btc-rpc-explorer.env 2>/dev/null
    sed -i "s/^BTCEXP_BASIC_AUTH_PASSWORD=.*/BTCEXP_BASIC_AUTH_PASSWORD=${newPassword}/g" /home/bitcoin/.config/btc-rpc-explorer.env 2>/dev/null
  fi

  # BTCPayServer
  if [ "${BTCPayServer}" == "on" ]; then
    echo "# changing BTCPAYSERVER password"
    sed -i "s/^btc.rpc.password=.*/btc.rpc.password=${newPassword}/g" /home/btcpay/.nbxplorer/Main/settings.config 2>/dev/null
  fi

  echo "# OK -> RPC Password B changed"
  echo "# Reboot is needed"
  exit 0

############################
# PASSWORD C
elif [ "${abcd}" = "c" ]; then

  if [ ${#newPassword} -gt 0 ]; then
    echo "New password C cannot be set thru paramter .. will start interactive password setting."
    echo "PRESS ENTER to continue"
    read key
  fi

  clear
  echo ""
  echo "****************************************************************************"
  echo "Change LND Wallet Password --> lncli --chain=${network} --network=${chain}net changepassword"
  echo "****************************************************************************"
  echo "This is your Password C on the RaspiBlitz to unlock your LND wallet."
  echo "If you had Auto-Unlock active - you need to re-activate after this."
  echo "****************************************************************************"

  echo "LND needs to be restarted to lock wallet first .. (please wait)"
  sudo systemctl restart lnd
  sleep 6

  # let LND-CLI handle the password change
  sudo -u bitcoin lncli --chain=${network} --network=${chain}net changepassword

  # deactivate AUTO-UNLOCK if activated
  echo ""
  echo "# Make sure Auto-Unlocks off"
  sudo /home/admin/config.scripts/lnd.autounlock.sh off

  # final user output
  echo ""
  echo "OK"
  exit 0

############################
# PASSWORD D
elif [ "${abcd}" = "d" ]; then

  echo "#### NOTICE ####"
  echo "Sorry - the password D cannot be changed. Its the password you set on creating your wallet to protect your seed (the list of words)."
  exit 1

############################
# PASSWORD X
elif [ "${abcd}" = "x" ]; then

    # second parameter is the flexible text
    text=$2
    resultFile=$3
    shred $3 2>/dev/null

    # ask user for new password (first time)
    dialog --backtitle "RaspiBlitz"\
       --insecure --passwordbox "${text}:\n(min 8chars, 1word, chars+number, no specials)" 10 52 2>$_temp

    # get user input
    password1=$( cat $_temp )
    shred $_temp

    # ask user for new password A (second time)
    dialog --backtitle "RaspiBlitz - Setup"\
       --insecure --passwordbox "Re-Enter the Password:\n(to test if typed in correctly)" 10 52 2>$_temp

    # get user input
    password2=$( cat $_temp )
    shred $_temp

    # check if passwords match
    if [ "${password1}" != "${password2}" ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Passwords dont Match\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh x "$2" "$3"
      exit 1
    fi

    # password zero
    if [ ${#password1} -eq 0 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Password cannot be empty\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh x "$2" "$3"
      exit 1
    fi

    # check that password does not contain bad characters
    clearedResult=$(echo "${password1}" | tr -dc '[:alnum:]-.' | tr -d ' ')
    if [ ${#clearedResult} != ${#password1} ] || [ ${#clearedResult} -eq 0 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Contains bad characters (spaces, special chars)\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh x "$2" "$3"
      exit 1
    fi

    # password longer than 8
    if [ ${#password1} -lt 8 ]; then
      dialog --backtitle "RaspiBlitz - Setup" --msgbox "FAIL -> Password length under 8\nPlease try again ..." 6 52
      sudo /home/admin/config.scripts/blitz.setpassword.sh x "$2" "$3"
      exit 1
    fi

    # store result is file
    echo "${password1}" > ${resultFile}
    
# everything else
else
  echo "FAIL: there is no password '${abcd}' (reminder: use lower case)"
  exit 1
fi