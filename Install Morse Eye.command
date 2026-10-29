#!/bin/bash
# Double-click to build Morse Eye and install it in your Applications folder.
cd "$(dirname "$0")/MacApp" && ./build-app.sh
echo
read -n 1 -s -r -p "Press any key to close this window."
