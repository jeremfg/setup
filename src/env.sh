# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Utilities for manipulating environment variables

if [[ -z ${GUARD_ENV_SH} ]]; then
  GUARD_ENV_SH=1
else
  return 0
fi

# Backup the current environment variables
var_backup() {
  sg_var_backup
  return $?
}

# Append a variable to the current backup
#
# Parameters:
#   $1[in]: Name of the variable
#   $2[value]: Value of the variable
# Returns:
#   0: If added succesfully
#   1: If no backup exists
var_append() {
  local name="$1"
  local value="$2"

  if [[ -f ${SG_ENV_FILE_BACKUP} ]]; then
    echo "declare -- ${name}=${value}" >>"${SG_ENV_FILE_BACKUP}"
    logInfo "\"${name}\" was appended"
  else
    logError "No backup file found: ${SG_ENV_FILE_BACKUP}"
    return 1
  fi

  return 0
}

# Clear all environment variables
var_clear() {
  local name

  while IFS='=' read -r name _; do
    logTrace "Clearing \"${name}\""
    unset "${name}"
  done < <(declare -p | cut -d' ' -f3 || true)

  return 0
}

# Restore previously backed up environment variables
#
# Returns:
#   0: If variables were restored succesfully
#   1: If backup was not found
var_restore() {
  sg_var_restore
  return $?
}

# https://askubuntu.com/a/1463894
# Adds an environment variable to bashrc
#
# @param[in] $1: Name of the env variable
# @param[in] $2: Value of the env variable
#
# return: 0 if successful, 1 otherwise
env_add() {
  if [[ -z "$1" ]] || [[ -z "$2" ]]; then
    echo "Expected 2 non-empty arguments"
    return 1
  fi

  local rcFile="${HOME}/.bashrc"
  local prop="$1" # export property to insert
  local val="$2"  # the desired value

  if grep -q "^export ${prop}=" "${rcFile}"; then
    sed -i "s,^export ${prop}=.*$,export ${prop}=${val}," "${rcFile}"
    logInfo "[updated] export ${prop}=${val}"
  else
    echo -e "export ${prop}=${val}" >>"${rcFile}"
    logInfo "[inserted] export ${prop}=${val}"
  fi

  # shellcheck disable=SC1090
  source "${rcFile}"

  return 0
}

# https://askubuntu.com/a/1463894
# Removes an environment variable to bashrc
#
# Parameters:
#   $1[in]: Name of the env variable to delete
# Returns:
#   0: If successfully removed
env_del() {
  if [[ -z "$1" ]]; then
    echo "Expected 1 non-empty arguments"
    return 1
  fi

  local rcFile=~/.bashrc
  local prop="$1"

  if grep -q "^export ${prop}=" "${rcFile}"; then
    sed -i "/^export ${prop}=.*$/d" "${rcFile}"
    unset "${prop}"
    logInfo "[deleted] export ${prop}"

    return 0
  else
    logError "[not found] export ${prop}"
    return 1
  fi
}

# Insert a configuration line if absent
#
# Parameters:
#   $1[in]: Configuration line
# Returns:
#   0: If config line is present
#   1: If we couldn't ensure the config is present
env_config() {
  local cfg_line="${1}"

  if [[ -z "${cfg_line}" ]]; then
    logError "Cannot configure an empty line"
    return 1
  fi

  local rcFile=~/.bashrc
  if ! os_add_config "${rcFile}" "${cfg_line}"; then
    return 1
  fi

  # shellcheck disable=SC1090
  source "${rcFile}"

  return 0
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
EV_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${EV_SOURCE}" ]]; do # resolve $EV_SOURCE until the file is no longer a symlink
  EV_ROOT=$(cd -P "$(dirname "${EV_SOURCE}")" >/dev/null 2>&1 && pwd)
  EV_SOURCE=$(readlink "${EV_SOURCE}")
  [[ ${EV_SOURCE} != /* ]] && EV_SOURCE=${EV_ROOT}/${EV_SOURCE} # if $EV_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
EV_ROOT=$(cd -P "$(dirname "${EV_SOURCE}")" >/dev/null 2>&1 && pwd)
EV_ROOT=$(realpath "${EV_ROOT}/..")

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
if ! source "${EV_ROOT}/src/os.sh"; then
  logFatal "Failed to import os.sh"
fi
if ! source "${EV_ROOT}/src/setup_git"; then
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
