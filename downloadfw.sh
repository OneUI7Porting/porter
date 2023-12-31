#!/usr/bin/env bash
#
# Copyright (C) 2023 BlackMesa123
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# shellcheck disable=SC1091

set -e

# Fixed directory for ODIN_DIR
ODIN_DIR="$HOME/odin_firmwares"

# Check if npm is installed, and install it if not
if ! command -v npm &> /dev/null; then
    echo "npm not found. Installing npm..."
    sudo apt-get update
    sudo apt-get install -y npm
fi

# Check if samfirm is installed, and install it if not
if ! command -v samfirm &> /dev/null; then
    echo "samfirm not found. Cloning samfirm.js repository and installing dependencies..."
    git clone https://github.com/jesec/samfirm.js.git
    cd samfirm.js
    npm install
    npm run build
    # Make samfirm executable globally
    sudo /home/j0sh1x/.nvm/versions/node/v21.4.0/bin/npm install -g .
    cd ..
fi

# Function to get the latest firmware version
GET_LATEST_FIRMWARE() {
    curl -s --retry 5 --retry-delay 5 "https://fota-cloud-dn.ospserver.net/firmware/$REGION/$MODEL/version.xml" \
        | grep latest | sed 's/^[^>]*>//' | sed 's/<.*//'
}

# Function to download firmware
DOWNLOAD_FIRMWARE() {
    local PDR
    PDR="$(pwd)"

    cd "$ODIN_DIR"
    { samfirm -m "$MODEL" -r "$REGION" > /dev/null; } 2>&1 \
        && touch "$ODIN_DIR/${MODEL}_${REGION}/.downloaded" \
        || exit 1
    [ -f "$ODIN_DIR/${MODEL}_${REGION}/.downloaded" ] && {
        echo -n "$(find "$ODIN_DIR/${MODEL}_${REGION}" -name "AP*" -exec basename {} \; | cut -d "_" -f 2)/"
        echo -n "$(find "$ODIN_DIR/${MODEL}_${REGION}" -name "CSC*" -exec basename {} \; | cut -d "_" -f 3)/"
        echo -n "$(find "$ODIN_DIR/${MODEL}_${REGION}" -name "CP*" -exec basename {} \; | cut -d "_" -f 2)"
    } >> "$ODIN_DIR/${MODEL}_${REGION}/.downloaded"

    echo ""
    cd "$PDR"
}

# Main script

FORCE=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        "-f" | "--force")
            FORCE=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 [options] MODEL REGION"
    echo " -f, --force : Force firmware download"
    exit 1
fi

MODEL="$1"
REGION="$2"

mkdir -p "$ODIN_DIR"

if [ -f "$ODIN_DIR/${MODEL}_${REGION}/.downloaded" ]; then
    [ -z "$(GET_LATEST_FIRMWARE)" ] && exit 0
    if [[ "$(GET_LATEST_FIRMWARE)" != "$(cat "$ODIN_DIR/${MODEL}_${REGION}/.downloaded")" ]]; then
        if $FORCE; then
            echo "- Updating $MODEL firmware with $REGION CSC..."
            rm -rf "$ODIN_DIR/${MODEL}_${REGION}" && DOWNLOAD_FIRMWARE
        else
            echo    "- $MODEL firmware with $REGION CSC already downloaded"
            echo    "  A newer version of this device's firmware is available."
            echo -e "  To download, clean your Odin firmwares directory or run this cmd with \"--force\"\n"
            exit 0
        fi
    else
        echo -e "- $MODEL firmware with $REGION CSC already downloaded\n"
        exit 0
    fi
else
    echo "- Downloading $MODEL firmware with $REGION CSC..."
    rm -rf "$ODIN_DIR/${MODEL}_${REGION}" && DOWNLOAD_FIRMWARE
fi

exit 0
