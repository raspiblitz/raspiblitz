#!/bin/bash

function set_variables() {

  declare -A params
  while (("$#")); do
    case "$1" in
    --pack)
      params[pack]="$2"
      shift 2
      ;;
    --github_user)
      params[github_user]="$2"
      shift 2
      ;;
    --branch)
      params[branch]="$2"
      shift 2
      ;;
    # arm64-rpi
    --image_link)
      params[image_link]="$2"
      shift 2
      ;;
    # arm64-rpi
    --image_checksum)
      params[image_checksum]="$2"
      shift 2
      ;;
    # amd64
    # preseed.cfg
    --preseed_file)
      params[preseed_file]="$2"
      shift 2
      ;;
    # amd64
    # uefi | bios
    --boot)
      params[boot]="$2"
      shift 2
      ;;
    # amd64
    # none | gnome
    --desktop)
      params[desktop]="$2"
      shift 2
      ;;
    --image_size)
      params[image_size]="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Error: Invalid argument"
      exit 1
      ;;
    esac
  done

  # Reset the global vars string
  vars=""
  # Iterate over all keys in the params array
  for key in "${!params[@]}"; do
    # If the value for this key is not empty, add it to vars
    if [ -n "${params[$key]}" ]; then
      vars="$vars -var $key=${params[$key]}"
    fi
  done

  export vars

}
