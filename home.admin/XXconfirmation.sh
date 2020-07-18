#!/bin/bash

confirmation()
{
  text=$1
  defaultno=$2
  height=$3
  width=$4

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
