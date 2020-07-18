#!/bin/bash

confirmation()
{
  local text=$1
  local defaultno=$2
  local height=$3
  local width=$4

  if [ $defaultno ]; then
     whiptail --title " Confirmation " --defaultno --yes-button "Yes" --no-button "No" --yesno " $1 

 Are you sure?
  " $height $width
  else
    whiptail --title " Confirmation " --yes-button "Yes" --no-button "No" --yesno " $1 

 Are you sure?
  " $height $width
  fi
  return $?
}
