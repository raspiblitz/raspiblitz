#!/bin/bash

set -e

echo "************* Vagrant provisioning ********************"

echo 'linking development files'
source_dir=/vagrant/home.admin
dest_dir=$HOME

cd $source_dir
for f in *; do
    if [ "$f" = "assets" ] ; then
        continue
    fi

    source_file="$source_dir/$f"
    dest_file="$dest_dir/$f"

    if [ -L $dest_file ] && [ "$(readlink "$dest_file")" = "$source_file" ]; then
            continue
    fi

    rm -rf "$dest_file"
    ln -s "$source_file" "$dest_file"
done
