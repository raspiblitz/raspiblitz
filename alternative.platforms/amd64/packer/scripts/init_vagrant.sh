#!/bin/bash

set -e

echo "************* Vagrant provisioning ********************"


if ! [ -e /dev/sdb1 ]; then
    echo 'Data drive partitioning'

    echo 'type=83' | sudo sfdisk /dev/sdb
fi


echo 'linking development files'
source_dir=/vagrant/home.admin
dest_dir=$HOME

cd $source_dir
for f in *; do
    source_file="$source_dir/$f"
    dest_file="$dest_dir/$f"

    if [ -L $dest_file ] && [ "$(readlink "$dest_file")" = "$source_file" ]; then
            continue
    fi

    rm -rf "$dest_file"
    ln -s "$source_file" "$dest_file"
done
