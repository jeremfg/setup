#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure SOPS

if [[ -z ${GUARD_SOPS_SH} ]]; then
  GUARD_SOPS_SH=1
else
  return
fi

# Install SOPS (if not already installed)
#
# Parameters:
sops_install() {
  if command -v sops &>/dev/null; then
    logInfo "SOPS is already installed"
    return 0
  fi

  logTrace "Installing SOPS"
  local cur_os
  os_identify cur_os
  local fct_name="sops_install_${cur_os}"
  local res
  ${fct_name}
  res=$?
  if [[ $res -eq 0 ]]; then
    if command -v sops &>/dev/null; then
      logInfo "SOPS was installed successfully"
      return 0
    else
      logError "Could not detect SOPS installation"
      return 1
    fi
  fi
  
  return $?
}

# Untested
sops_install_ubuntu() {
  local url="${SOPS_URL_BASE}${SOPS_DEBIAN}"
  local installer="$(basename ${url})"
  local location
  if git_find_root location "${SO_ROOT}"; then
    location="${location}/bin/downloads/${installer}"
    if [[ ! -f "${location}" ]]; then
      if ! mkdir -p "$(dirname ${location})"; then
        logError "Failed to create directory for SOPS installer"
        return 1
      fi
      logTrace "Downloading into ${location} from ${url}"
      if ! curl -sSL -o "${location}" "${url}"; then
        logError "Failed to download SOPS installer"
        return 1
      fi
    fi
    if ! sudo apt install -y ${location}; then
      logError "Failed to install SOPS"
      return 1
    fi
  else
    logError "Failed to find the root of the repository"
    return 1
  fi
}

sops_install_centos() {
  local url="${SOPS_URL_BASE}${SOPS_REDHAT}"
  local installer="$(basename ${url})"
  local location
  if git_find_root location "${SO_ROOT}"; then
    location="${location}/bin/downloads/${installer}"
    if [[ ! -f "${location}" ]]; then
      if ! mkdir -p "$(dirname ${location})"; then
        logError "Failed to create directory for SOPS installer"
        return 1
      fi
      logTrace "Downloading into ${location} from ${url}"
      if ! curl -sSLo "${location}" "${url}"; then
        logError "Failed to download SOPS installer"
        return 1
      fi
    fi
    if ! sudo yum install -y ${location}; then
      logError "Failed to install SOPS"
      return 1
    fi
  else
    logError "Failed to find the root of the repository"
    return 1
  fi
}

# Constants

SOPS_VERSION="3.9.1"
SOPS_URL_BASE="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/"
SOPS_REDHAT="sops-${SOPS_VERSION}-1.x86_64.rpm"
SOPS_DEBIAN="sops_${SOPS_VERSION}_amd64.deb"

###########################
###### Startup logic ######
###########################

SO_ARGS=("$@")
SO_CWD=$(pwd)
SO_ME="$(basename "$0")"

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

# Import dependencies
source ${SO_ROOT}/src/slf4sh.sh
source ${SO_ROOT}/src/os.sh
source ${SO_ROOT}/src/git.sh

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  echo "ERROR: This script cannot be piped"
  exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  echo "ERROR: This script cannot be exceuted"
  exit 1
fi