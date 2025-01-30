# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Shell utilities

# Execute a function on the current shell
#
# Parameters:
#   $0[out]: Console output from executing the command
#   $@[in]: Command to execute
# Returns:
#   1: Error executing the command
#   *: Return Code from the command
sh_exec() {
  local __result_stdout="${1}"
  shift

  # Check if executable exists
  if ! command -v "${1}" &>/dev/null; then
    logError "Command \"${1}\" does not exist"
  fi

  local __result __return_code
  logTrace "Executing: ${*}"
  __result=$("${@}" 2>&1)
  __return_code=$?

  if [[ ${__return_code} -ne 0 ]]; then
    logError <<EOF
Failed to Execute: ${@}

Return Code: ${__return_code}
Output:
${__result}
EOF
  else
    logTrace "Executed successfully\n${__result}"
  fi

  if [[ -n "${__result_stdout}" ]]; then
    eval "${__result_stdout}='${__result}'"
  fi

  # shellcheck disable=SC2248
  return ${__return_code}
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
SHU_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${SHU_SOURCE}" ]]; do # resolve $SHU_SOURCE until the file is no longer a symlink
  SHU_ROOT=$(cd -P "$(dirname "${SHU_SOURCE}")" >/dev/null 2>&1 && pwd)
  SHU_SOURCE=$(readlink "${SHU_SOURCE}")
  [[ ${SHU_SOURCE} != /* ]] && SHU_SOURCE=${SHU_ROOT}/${SHU_SOURCE} # if $SHU_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SHU_ROOT=$(cd -P "$(dirname "${SHU_SOURCE}")" >/dev/null 2>&1 && pwd)
SHU_ROOT=$(realpath "${SHU_ROOT}/..")

# Determine BPKG's global prefix
if [[ -z "${PREFIX}" ]]; then
  if [[ $(id -u || true) -eq 0 ]]; then
    PREFIX="/usr/local"
  else
    PREFIX="${HOME}/.local"
  fi
fi

# shellcheck disable=SC1091
if ! source "${PREFIX}/lib/slf4.sh"; then
  echo "Failed to import slf4.sh"
  exit 1
fi

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  logFatal "This script cannot be piped"
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  logFatal "This script cannot be exceuted"
fi
