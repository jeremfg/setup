# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure OS packages

if [[ -z ${GUARD_PKG_SH} ]]; then
  GUARD_PKG_SH=1
else
  return 0
fi

pkg_install_from() {
  sg_pkg_install_from "$@"
  return $?
}

# Install the package specified (if not already installed)
#
# Parameters:
#   $@: List of packages
pkg_install() {
  sg_pkg_install "$@"
  return $?
}

###########################
###### Startup logic ######
###########################

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
fi
if ! source "${PK_ROOT}/src/os.sh"; then
  logFatal "Failed to import os.sh"
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
