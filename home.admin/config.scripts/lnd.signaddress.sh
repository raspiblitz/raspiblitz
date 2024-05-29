#!/bin/bash

# This script allows users to sign a message from a specific Bitcoin address
# either by generating a new address or using an existing one.

# Ask if a new address should be generated or an existing one should be entered
read -p "Do you want to generate a new address? (y/n) " generate_new

# 1.a. If generating a new address, ask for the address type
if [ "$generate_new" == "y" ]; then
    echo "Generate a wallet new address. Address-types has to be one of:"
    echo "1. p2wkh:  Pay to witness key hash"
    echo "2. np2wkh: Pay to nested witness key hash"
    echo "3. p2tr:   Pay to taproot pubkey"
    read -p "Enter the address type (1-3 or string): " address_type
    case "$address_type" in
        1|"p2wkh")
            address_type="p2wkh"
            ;;
        2|"np2wkh")
            address_type="np2wkh"
            ;;
        3|"p2tr")
            address_type="p2tr"
            ;;
        *)
            echo "Error: Invalid address type."
            exit 1
            ;;
    esac
    address=$(lncli newaddress $address_type)
    address_variable=$(echo $address | jq -r '.address')
else
    # 1.b. Check if the manually entered address is valid
    read -p "Enter the existing address: " address
    if ! bitcoin-cli validateaddress "$address" | grep -q "isvalid\": true"; then
        echo "Error: The entered address is not valid."
        exit 1
    fi
    address_variable=$address
fi
# 2. Ask for the message to sign and save it to a variable
read -p "Enter the message to sign: " message_to_sign

# 3. Execute the lncli wallet addresses signmessage command
signature_js=$(lncli wallet addresses signmessage --address $address_variable --msg "$message_to_sign")
signature=$(echo $signature_js | jq -r '.signature')
echo "The address is: $address_variable"
echo "The message to sign is: $message_to_sign"
echo "The signature is: $signature"
