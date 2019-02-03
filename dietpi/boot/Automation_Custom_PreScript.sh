#as described in https://github.com/Fourdee/DietPi/issues/2488
mkdir -p /etc/profile.d
> /etc/profile.d/dietpi-debug.sh
dietpi-update
rm  /etc/profile.d/dietpi-debug.sh