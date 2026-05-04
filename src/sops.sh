# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure SOPS

if [[ -z ${GUARD_SOPS_SH+x} ]]; then
  GUARD_SOPS_SH=1
else
  return 0
fi

############################################
## Configuration
############################################

SOPS_VERSION="3.9.1"
SOPS_URL_BASE="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/"
SOPS_REDHAT="sops-${SOPS_VERSION}-1.x86_64.rpm"
SOPS_DEBIAN="sops_${SOPS_VERSION}_amd64.deb"

# Install SOPS (if not already installed)
#
# Parameters:
sops_install() {
  if command -v sops &>/dev/null; then
    logInfo "SOPS is already installed"
    return 0
  elif [[ -z "${DOWNLOAD_DIR}" ]]; then
    logError "DOWNLOAD_DIR is not set"
    return
  elif [[ ! -d "${DOWNLOAD_DIR}" ]]; then
    if ! file_ensure_dir "${DOWNLOAD_DIR}"; then
      logError "Failed to create DOWNLOAD_DIR at ${DOWNLOAD_DIR}"
      return 1
    fi
  fi

  logTrace "Installing SOPS"
  local cur_os
  os_identify cur_os
  local fct_name="sops_install_${cur_os}"
  if ${fct_name}; then
    if command -v sops &>/dev/null; then
      logInfo "SOPS was installed successfully"
      return 0
    else
      logError "Could not detect SOPS installation"
      return 1
    fi
  else
    return 1
  fi
}

# Untested
sops_install_ubuntu() {
  local url location
  url="${SOPS_URL_BASE}${SOPS_DEBIAN}"

  if ! web_download location "${url}" "${DOWNLOAD_DIR}"; then
    logError "Failed to download SOPS installer"
    return 1
  fi

  if ! sudo apt install -y "${location}"; then
    logError "Failed to install SOPS"
    return 1
  fi
}

sops_install_centos() {
  local url location
  url="${SOPS_URL_BASE}${SOPS_REDHAT}"

  if ! web_download location "${url}" "${DOWNLOAD_DIR}"; then
    logError "Failed to download SOPS installer"
    return 1
  fi

  if ! sudo yum install -y "${location}"; then
    logError "Failed to install SOPS"
    return 1
  fi
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
SO_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${SO_SOURCE}" ]]; do # resolve $SO_SOURCE until the file is no longer a symlink
  SO_ROOT=$(cd -P "$(dirname "${SO_SOURCE}")" >/dev/null 2>&1 && pwd)
  SO_SOURCE=$(readlink "${SO_SOURCE}")
  [[ ${SO_SOURCE} != /* ]] && SO_SOURCE=${SO_ROOT}/${SO_SOURCE} # if $SO_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SO_ROOT=$(cd -P "$(dirname "${SO_SOURCE}")" >/dev/null 2>&1 && pwd)
SO_ROOT=$(realpath "${SO_ROOT}/..")

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
elif ! source "${SO_ROOT}/src/constants.sh"; then
  logFatal "Failed to import constants.sh"
elif ! source "${SO_ROOT}/src/os.sh"; then
  logFatal "Failed to import os.sh"
elif ! source "${SO_ROOT}/src/git.sh"; then
  logFatal "Failed to import git.sh"
elif ! source "${SO_ROOT}/src/file.sh"; then
  logFatal "Failed to import file.sh"
elif ! source "${SO_ROOT}/src/web.sh"; then
  logFatal "Failed to import web.sh"
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
