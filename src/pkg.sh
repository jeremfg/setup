#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure OS packages

if [[ -z ${GUARD_PKG_SH} ]]; then
  GUARD_PKG_SH=1
else
  return
fi

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

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
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