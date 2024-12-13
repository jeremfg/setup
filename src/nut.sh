#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure NUT (Network UPS Tools)

if [[ -z ${GUARD_NUT_SH} ]]; then
  GUARD_NUT_SH=1
else
  return
fi

nut_setup() {
  if ! pkg_install_from "epel" "nut" "nut-client"; then
    logError "Failed to install NUT"
    return 1
  fi
}

###########################
###### Startup logic ######
###########################

NU_ARGS=("$@")
NU_CWD=$(pwd)
NU_ME="$(basename "$0")"

# Get directory of this script
# https://stackoverflow.com/a/246128
NU_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${NU_SOURCE}" ]]; do # resolve $NU_SOURCE until the file is no longer a symlink
  NU_ROOT=$(cd -P "$(dirname "${NU_SOURCE}")" >/dev/null 2>&1 && pwd)
  NU_SOURCE=$(readlink "${NU_SOURCE}")
  [[ ${NU_SOURCE} != /* ]] && NU_SOURCE=${NU_ROOT}/${NU_SOURCE} # if $NU_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
NU_ROOT=$(cd -P "$(dirname "${NU_SOURCE}")" >/dev/null 2>&1 && pwd)
NU_ROOT=$(realpath "${NU_ROOT}/..")

# Import dependencies
source ${NU_ROOT}/src/slf4sh.sh

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  echo "ERROR: This script cannot be piped"
  exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  # echo "ERROR: This script cannot be exceuted"
  # exit 1
  nut_setup
fi
