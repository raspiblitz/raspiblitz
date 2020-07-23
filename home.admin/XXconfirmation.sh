#!/bin/bash

confirmation()
{
  local text=$1
  local yesButtonText=$2
  local noButtonText=$3
  local defaultno=$4
  local height=$5
  local width=$6
  local answer=-100

  if [ $defaultno ]; then
     whiptail --title " Confirmation " --defaultno --yes-button "$yesButtonText" --no-button "$noButtonText" --yesno " $text

  " $height $width
  else
    whiptail --title " Confirmation " --yes-button "$yesButtonText" --no-button "$noButtonText" --yesno " $text

  " $height $width
  fi
  answer=$?
  return $answer
}
