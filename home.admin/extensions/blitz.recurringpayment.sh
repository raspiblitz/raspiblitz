# The variable below is pulled in by Raspiblitz and makes this script a "supported" extension.
BLITZ_EXT_NAME="Set up a recurring payment"
HEIGHT=19
WIDTH=120

# Denomination menu options
OPTIONS=(SATS "Send sats" \
         USD "Send sats denominated in dollars")

# Crontab (send frequency) menu options
FREQUENCY_OPTIONS=(DAILY "Send sats every day" \
                   WEEKLY "Send sats once a week, every Sunday"
                   MONTHLY "Send sats once a month, on the 1st"
                   YEARLY "Send sats once a year, on January 1st")


# Detect if the user has cancelled running the script at any point in time.
function cancel_check(){
  if [[ -z "$1" ]]; then
    echo "Cancelled"
    exit 0
  fi
}

# User select sats or dollars to denominate in.
DENOMINATION=$(dialog --clear \
        --backtitle "Recurring Payments" \
        --title "Recurring Keysend" \
        --ok-label "Select" \
        --cancel-label "Exit" \
        --menu "Automatically send some sats to another node on a daily/weekly/monthly basis." \
        $HEIGHT $WIDTH $HEIGHT \
        "${OPTIONS[@]}" \
        2>&1 >/dev/tty)

cancel_check $DENOMINATION

# After choosing denomination, ask user how many dollars or sats to send
case $DENOMINATION in
      SATS)
        AMOUNT=$(dialog --backtitle "Recurring Payments" \
            --title "Choose the amount" \
            --inputbox "Enter the amount to send in $DENOMINATION" \
            10 60 100 2>&1 >/dev/tty)
        ;;
      USD)
        AMOUNT=$(dialog --backtitle "Recurring Payments" \
            --title "Choose the amount" \
            --inputbox "Enter the amount to send in $DENOMINATION" \
            10 60 0.50 2>&1 >/dev/tty)
        ;;
esac

cancel_check $AMOUNT

# Ask user for node ID to send to.
NODE_ID=$(whiptail --backtitle "Recurring Payments" \
            --title "Node Address" \
            --inputbox "Enter the 66-character public key of the node you'd like to send to.
            \n(e.g: 02c3afc714b2ea1d4ec35e5d4c6a... )" \
            10 60 2>&1 >/dev/tty)

cancel_check $NODE_ID

# Ask user how frequently they'd like to send sats
FREQUENCY=$(dialog --clear \
        --backtitle "Recurring Payments" \
        --title "Select Frequency" \
        --ok-label "Select" \
        --cancel-label "Exit" \
        --menu "How often do you want to send sats to this node?" \
        $HEIGHT $WIDTH $HEIGHT \
        "${FREQUENCY_OPTIONS[@]}" \
        2>&1 >/dev/tty)

case $FREQUENCY in
      DAILY)
        cron_prefix="0 0 * * *"
        ;;
      WEEKLY)
        cron_prefix="0 0 * * 0"
        ;;
      MONTHLY)
        cron_prefix="0 0 1 * *"
        ;;
      YEARLY)
        cron_prefix="0 0 1 1 *"
        ;;
esac

cancel_check $cron_prefix

# Generate a keysend script
short_node_id=$(echo $NODE_ID | cut -c 1-7)
script_name="/home/admin/extensions/_${short_node_id}_keysend.sh"
denomination=$(echo $DENOMINATION | tr '[:upper:]' '[:lower:]')
echo -n "/usr/bin/python /home/admin/extensions/_recurringpayment.py " \
      "--$denomination $AMOUNT " \
      "--node_id $NODE_ID " \
      > $script_name
chmod +x $script_name

# Display crontab line
path='$HOME/.profile; PATH=$PATH:/usr/local/bin'
command="$cron_prefix . $path $script_name"
clear
printf "No sats are being sent yet! Type 'crontab -e' to edit your crontab, then paste in the following line:\n"
echo "$command"
printf "\nPress enter when done."
read
