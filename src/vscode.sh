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
  # Add Microsoft GPG key
  elif ! wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "${SETUP_TMP_DIR}/packages.microsoft.gpg"; then
    logError "Failed to download Microsoft GPG key"
    return 1
  elif ! sudo install -D -o root -g root -m 644 "${SETUP_TMP_DIR}/packages.microsoft.gpg" "${SETUP_APT_KEYRING_DIR}/packages.microsoft.gpg"; then
    logError "Failed to install Microsoft GPG key"
    rm -f "${SETUP_TMP_DIR}/packages.microsoft.gpg"
    return 1
  fi
  rm -f "${SETUP_TMP_DIR}/packages.microsoft.gpg"

  # Add VS Code repository
  echo "deb [arch=amd64,arm64,armhf signed-by=${SETUP_APT_KEYRING_DIR}/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
    sudo tee "${SETUP_APT_SOURCES_DIR}/vscode.list" > /dev/null

  # Update package cache and install
  if ! sudo apt-get update; then
    logError "Failed to update package cache"
    return 1
  elif ! pkg_install code; then
    logError "Failed to install VS Code"
    return 1
  fi

  logInfo "VS Code installed successfully"
  return 0
}

#############################
###### Local constants ######
#############################

# Default shared constants when sourced without constants.sh
if [[ -z "${SETUP_TMP_DIR+x}" ]]; then SETUP_TMP_DIR=""; fi
if [[ -z "${SETUP_APT_KEYRING_DIR+x}" ]]; then SETUP_APT_KEYRING_DIR=""; fi
if [[ -z "${SETUP_APT_SOURCES_DIR+x}" ]]; then SETUP_APT_SOURCES_DIR=""; fi

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
VS_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${VS_SOURCE}" ]]; do # resolve $VS_SOURCE until the file is no longer a symlink
  VS_ROOT=$(cd -P "$(dirname "${VS_SOURCE}")" >/dev/null 2>&1 && pwd)
  VS_SOURCE=$(readlink "${VS_SOURCE}")
  [[ ${VS_SOURCE} != /* ]] && VS_SOURCE=${VS_ROOT}/${VS_SOURCE} # if $VS_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
VS_ROOT=$(cd -P "$(dirname "${VS_SOURCE}")" >/dev/null 2>&1 && pwd)
VS_ROOT=$(realpath "${VS_ROOT}/..")

# Determine BPKG's global prefix
if [[ -z "${PREFIX}" ]]; then
  if [[ $(id -u || true) -eq 0 ]]; then
    PREFIX="/usr/local"
  else
    PREFIX="${HOME}/.local"
  fi
fi

# Import dependencies
# shellcheck disable=SC1091
if ! source "${PREFIX}/lib/slf4.sh"; then
  echo "Failed to import slf4.sh"
  exit 1
elif ! source "${VS_ROOT}/src/constants.sh"; then
  logFatal "Failed to import constants.sh"
elif ! source "${VS_ROOT}/src/pkg.sh"; then
  logFatal "Failed to import pkg.sh"
fi

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  logFatal "This script cannot be piped"
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  logFatal "This script cannot be executed"
fi
