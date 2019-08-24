#!/bin/bash

echo ""
echo "You pressed B1 - preparing lightning invoice..."
echo "-----------------------------------------------"
sudo su - admin /home/admin/BBcreateInvoice.sh 0
echo ""
echo "-----------------------------------------------"
echo ""
/home/admin/00infoLCD.sh
