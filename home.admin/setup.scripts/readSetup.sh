# Source this helper with the setup file path. The format is a list of
# key=value records, optionally single-quoted (including a multiline seed display).
read_setup_records() {
  local line key value continuation
  local -A records=()
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    [[ "$line" = *=* ]] || return 1
    key=${line%%=*}
    value=${line#*=}
    case "$key" in
      hostname|network|chain|lightning|menuchoice|deleteData|systemCopy|formatHDD|cleanHDD|\
      passwordA|passwordB|passwordC|setPasswordA|setPasswordB|setPasswordC|\
      migrationFile|migrationOS|hddMigrateDeviceFrom|hddMigrateDeviceTo|hddMigration|uploadMigration|\
      lndrescue|clrescue|seedWords|seedPassword|seedwordsNEW|seedwords6x4NEW|staticchannelbackup) ;;
      *) return 1 ;;
    esac
    if [[ "$value" = "'"* ]]; then
      value=${value:1}
      while [[ "$value" != *"'" ]]; do
        [ "$key" = seedwords6x4NEW ] || return 1
        IFS= read -r continuation || return 1
        value+=$'\n'"$continuation"
      done
      value=${value%\'}
    fi
    records["$key"]=$value
  done < "$1" || return 1
  for key in "${!records[@]}"; do
    printf -v "$key" '%s' "${records[$key]}"
  done
}
read_setup_records "$1"
