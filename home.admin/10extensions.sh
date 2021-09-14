# Loop through extensions folder, adding scripts to the list
extensions_list=()
: ${DIALOG_YES=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_JUSTRUN=3}

HEIGHT=19
WIDTH=80

IFS=""
for FILE in /home/admin/extensions/*
do
	fname=$(basename $FILE)

	# Don't add files that begin with an underscore to script list (eg: _function.sh)
	if [[ "$fname" == _* ]]; then
		continue
	fi

  # Detect script name from head of file. Skip over scripts that don't have a name.
  detected_name=$(head $FILE | grep BLITZ_EXT_NAME | awk -F "=" '{print $2}' | tr -d \")
  if [[ ! -z "$detected_name" ]]; then
    extensions_list+=( "$fname " )
    extensions_list+=( "$detected_name " )
  fi
done

# Display extensions list
CHOICE=$(dialog --clear \
        --title "Extensions" \
        --ok-label "Select" \
        --cancel-label "Exit" \
        --menu "Select a script to run" \
        $HEIGHT $WIDTH $HEIGHT \
        ${extensions_list[@]} \
        2>&1 >/dev/tty)

CHOICE=$(echo $CHOICE | tr -d "[:blank:]")
if [[ -z "$CHOICE" ]]; then
  clear
  echo "Extension selection cancelled."
  exit 0
fi

# Display script to user, ask if they want to edit it.
dialog --title "Edit Script?" \
        --extra-button \
        --ok-label "Yes" \
        --extra-label "No, just run it" \
        --cr-wrap \
        --yesno "$(cat /home/admin/extensions/$CHOICE)" \
        $HEIGHT $WIDTH

return_value=$?

case $return_value in
  $DIALOG_YES)
    echo "$CHOICE"
    /home/admin/config.scripts/blitz.setconf.sh /home/admin/extensions/$CHOICE "root"
    dialog --title "Run script?" --yesno "Run $CHOICE?" 10 $WIDTH
    return_value=$?
    ;;
  $DIALOG_JUSTRUN)
    return_value=$DIALOG_YES
    ;;
  $DIALOG_CANCEL)
    return_value=$DIALOG_CANCEL
    ;;
esac

# Don't run if script edit was cancelled.
if [[ "$return_value" -ne "$DIALOG_CANCEL" ]]; then
  echo "running $CHOICE"
  /home/admin/extensions/$CHOICE
fi