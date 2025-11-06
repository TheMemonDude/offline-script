#!/bin/bash

# export ref_branch=test-mode domain=offline-app.local dbuser=postgres dbname=dummy_db dbpass=postgres123 && wget -qO- https://raw.githubusercontent.com/TheMemonDude/offline-script/refs/heads/main/boot.sh | bash

GITHUB_REPO="TheMemonDude/offline-script"

echo -e "\nCloning from: https://github.com/${GITHUB_REPO}.git"
rm -rf ~/.local/share/offline-script/
git clone "https://github.com/${GITHUB_REPO}.git" ~/.local/share/offline-script >/dev/null

echo -e "\nInstallation starting..."
source ~/.local/share/offline-script/install.sh
