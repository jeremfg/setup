#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script is used to identify the OS

os() {
  local myvar
  local res
  os_identify myvar
  res=$?
  if [[ $res -eq 0 ]]; then
    echo "${myvar}"
  fi
  return $res
}

# Identify the current OS
#
# Parameters:
#   $1[out]: Current OS
os_identify(){
  # Function is maintained in setup_git.sh
  sg_os_identify "${1}"
  return $?
}

# Ask user for input
#
# Parameters:
#   $1[out]: Answer
#   $2[in]: Question to ask
#   $3[in]: Default value (Optional)
#   $4[in]: Timout (s) [Default: 10 seconds]
os_ask_user() {
  local ans="$1"
  local question="$2"
  local default="$3"
  local -i timeout=${4:-10}

  # Implementation
  local myvar
  # Ask user for input
  if read -t ${timeout} -p "${question} [${default}]: " myvar; then
    if [[ -z "${myvar}" ]]; then
      eval "$ans='${default}'"
    else
      eval "$ans='${myvar}'"
    fi
  else
    echo ""
    eval "$ans='${default}'"
  fi
  return 0
}

###########################
###### Startup logic ######
###########################
OS_ARGS=("$@")
OS_CWD=$(pwd)
OS_ME="$(basename "$0")"

# Get directory of this script
# https://stackoverflow.com/a/246128
OS_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${OS_SOURCE}" ]]; do # resolve $OS_SOURCE until the file is no longer a symlink
  OS_ROOT=$(cd -P "$(dirname "${OS_SOURCE}")" >/dev/null 2>&1 && pwd)
  OS_SOURCE=$(readlink "${OS_SOURCE}")
  [[ ${OS_SOURCE} != /* ]] && OS_SOURCE=${OS_ROOT}/${OS_SOURCE} # if $OS_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
OS_ROOT=$(cd -P "$(dirname "${OS_SOURCE}")" >/dev/null 2>&1 && pwd)
OS_ROOT=$(realpath "${OS_ROOT}/..")

# Import dependencies
source ${OS_ROOT}/src/slf4sh.sh
source ${OS_ROOT}/src/setup_git.sh

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  echo "ERROR: This script cannot be piped"
  exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  LOG_CONSOLE=0 # Make sure logger is not outputting anything else on the console than what we want
  os "${@}"
  exit $?
fi
