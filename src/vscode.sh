# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# This script is used to install Visual Studio Code

if [[ -z ${GUARD_VSCODE_SH} ]]; then
  GUARD_VSCODE_SH=1
else
  return 0
fi

# Install VS Code from Microsoft's official repository
#
# Returns:
#   0: If VS Code is installed successfully or already installed
#   1: If installation fails
vscode_install() {
  if command -v code &>/dev/null; then
    logInfo "VS Code is already installed"
    return 0
  fi

  logInfo "Installing VS Code..."

  # Install dependencies
  if ! pkg_install wget gpg apt-transport-https; then
    logError "Failed to install VS Code dependencies"
    return 1
  fi

  # Add Microsoft GPG key
  if ! wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg; then
    logError "Failed to download Microsoft GPG key"
    return 1
  fi

  if ! sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg; then
    logError "Failed to install Microsoft GPG key"
    rm -f /tmp/packages.microsoft.gpg
    return 1
  fi
  rm -f /tmp/packages.microsoft.gpg

  # Add VS Code repository
  echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
    sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

  # Update package cache and install
  if ! sudo apt-get update; then
    logError "Failed to update package cache"
    return 1
  fi

  if ! pkg_install code; then
    logError "Failed to install VS Code"
    return 1
  fi

  logInfo "VS Code installed successfully"
  return 0
}
