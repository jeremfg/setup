# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# This script is used to identify the OS

if [[ -z ${GUARD_OS_SH} ]]; then
  GUARD_OS_SH=1
else
  return 0
fi

os() {
  local myvar
  local res
  os_identify myvar
  res=$?
  if [[ ${res} -eq 0 ]]; then
    echo "${myvar}"
  fi

  # shellcheck disable=SC2248
  return ${res}
}

# Identify the current OS
#
# Parameters:
#   $1[out]: Current OS
os_identify() {
  # Function is maintained in setup_git
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
  local res
  # Ask user for input, using timeout if default value is not empty
  if [[ -z "${default}" ]]; then
    # shellcheck disable=SC2162
    read -p "${question} [${default}]: " myvar </dev/tty
    res=$?
  else
    # shellcheck disable=SC2162
    read -t "${timeout}" -p "${question} [${default}]: " myvar </dev/tty
    res=$?
  fi
  if [[ ${res} -eq 0 ]]; then
    if [[ -z "${myvar}" ]]; then
      eval "${ans}='${default}'"
    else
      eval "${ans}='${myvar}'"
    fi
  else
    echo ""
    eval "${ans}='${default}'"
  fi
  return 0
}

###########################
###### Startup logic ######
###########################

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
elif ! source "${OS_ROOT}/src/constants.sh"; then
  logFatal "Failed to import constants.sh"
elif ! source "${OS_ROOT}/src/setup_git"; then
  logFatal "Failed to import setup_git"
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
