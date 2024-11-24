#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure OS packages

# Global variables
PK_UPDATED=0

# Install the package specified (if not already installed)
#
# Parameters:
#   $@: List of packages
pkg_install() {
  logInfo "Asked to install the following packages: $@"

  # First, check which OS we are running
  local cur_os
  if ! os_identify cur_os; then
    logError "Could not identify OS"
  fi

  # Functions we will need
  local fct_update
  local fct_is_installed
  local fct_install
  fct_update="pkg_update_${cur_os}"
  fct_is_installed="pkg_is_installed_${cur_os}"
  fct_install="pkg_install_${cur_os}"

  # Update catalog
  if [[ ${PK_UPDATED} -eq 0 ]]; then
    if ! eval "${fct_update}"; then
      logError "Failed to update catalog"
      return 1
    else
      logInfo "Catalog updated successfully"
      PK_UPDATED=1
    fi
  else
    logInfo "Catalog is already up to date"
  fi

  local to_install=()
  local cur_pkg
  local res
  # Check which packages need to be installed
  for cur_pkg in "$@"; do
    logInfo "Checking if package \"${cur_pkg}\" is alread installed"
    eval "${fct_is_installed}" "${cur_pkg}"
    res=$?
    if [[ $res -eq 2 ]]; then
      logError "Failed to check if package \"${cur_pkg}\" is installed"
      return 1
    elif [[ $res -eq 1 ]]; then
      logInfo "Package \"${cur_pkg}\" is not installed"
      to_install+=("${cur_pkg}")
    else
      logInfo "Package \"${cur_pkg}\" is already installed"
    fi
  done

  # Check if we have something to install
  if [[ ${#to_install[@]} -gt 0 ]]; then
    if ! eval ${fct_install} "${to_install[@]}"; then
      logError "Failed to install packages"
      return 1
    fi
  else
    logInfo "Nothing to install"
  fi

  return 0
}

pkg_update_centos() {
  logInfo "Nothing to update with yum"
  return 0
}

# Checks if a package is installed using yum
#
# Parameters:
#   $1: package to check
# Returns:
#   0: Package is installed
#   1: Package is not installed
#   2: Error
pkg_is_installed_centos() {
  local cur_pkg=$1
  local res=2

  if yum list installed "${cur_pkg}" &>/dev/null; then
    res=0
  else
    res=1
  fi

  return $res
}

# Install packages using yum
#
# Parameters:
#   $@: List of packages to install
pkg_install_centos() {
  local pkgs=("$@")

  if yum install -y "${pkgs[@]}"; then
    return 0
  else
    return 1
  fi
}

###########################
###### Startup logic ######
###########################

PK_ARGS=("$@")
PK_CWD=$(pwd)
PK_ME="$(basename "$0")"

# Get directory of this script
# https://stackoverflow.com/a/246128
PK_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${PK_SOURCE}" ]]; do # resolve $PK_SOURCE until the file is no longer a symlink
  PK_ROOT=$(cd -P "$(dirname "${PK_SOURCE}")" >/dev/null 2>&1 && pwd)
  PK_SOURCE=$(readlink "${PK_SOURCE}")
  [[ ${PK_SOURCE} != /* ]] && PK_SOURCE=${PK_ROOT}/${PK_SOURCE} # if $PK_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
PK_ROOT=$(cd -P "$(dirname "${PK_SOURCE}")" >/dev/null 2>&1 && pwd)
PK_ROOT=$(realpath "${PK_ROOT}/..")

# Import dependencies
source ${PK_ROOT}/src/slf4sh.sh
source ${PK_ROOT}/src/os.sh

if [[ -p /dev/stdin ]]; then
  # This script was piped
  echo "ERROR: This script cannot be piped"
  exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  pkg_install "${@}"
  exit $?
fi