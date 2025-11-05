#!/bin/bash

# dbname=dummy dbpass=123 wget -qO- https://example.com/boot.sh | bash

sudo apt update && sudo apt install -y git bzip2

GITHUB_REPO="TheMemonDude/offline-script"

echo -e "\nCloning from: https://github.com/${GITHUB_REPO}.git"
rm -rf ~/.local/share/offline-script/
git clone "https://github.com/${GITHUB_REPO}.git" ~/.local/share/offline-script >/dev/null

echo -e "\nInstallation starting..."
source ~/.local/share/offline-script/install.sh
