#!/bin/bash

sudo apt update && sudo apt install -y git

GITHUB_REPO="TheMemonDude/offline-script"

echo -e "\nCloning from: https://github.com/${GITHUB_REPO}.git"
rm -rf ~/.local/share/offline-script/
git clone "https://github.com/${GITHUB_REPO}.git" ~/.local/share/offline-script >/dev/null

echo -e "\nInstallation starting..."
source ~/.local/share/offline-script/install.sh
