#!/bin/bash

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 flash --partition image [--partition image ...]"
    exit 1
fi

if [[ "$1" != "flash" ]]; then
    echo "Error: The first argument must be 'flash'."
    echo "Usage: $0 flash --partition image [--partition image ...]"
    exit 1
fi

shift

while [[ $# -gt 0 ]]; do
    partition=$1
    image=$2

    if [[ "$partition" == --* && ! -z "$image" ]]; then
        partition_name=${partition#--}

        fastboot flash "$partition_name" "$image"

        shift 2
    else
        echo "Invalid input: $partition $image"
        echo "Usage: $0 flash --partition image [--partition image ...]"
        exit 1
    fi
done
