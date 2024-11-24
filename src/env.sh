#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Utilities for manipulating environment variables

ENV_FILE_BACKUP="/tmp/backup.env"

# Backup the current environment variables
var_backup() {
  declare -p > ${ENV_FILE_BACKUP}
  logInfo "Environment variables have been backed up to: ${ENV_FILE_BACKUP}"
  return 0
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

  if [[ -f ${ENV_FILE_BACKUP} ]]; then
    echo "declare -- ${name}=${value}" >> ${ENV_FILE_BACKUP}
    logInfo "\"${name}\" was appended"
  else
    logError "No backup file found: ${ENV_FILE_BACKUP}"
    return 1
  fi

  return 0
}

# Clear all environment variables
var_clear() {
  local name

  while IFS='=' read -r name _; do
    logTrace "Clearing \"${name}\""
    unset "$name"
  done < <(declare -p | cut -d' ' -f3)

  return 0
}

# Restore previously backed up environment variables
#
# Returns:
#   0: If variables were restored succesfully
#   1: If backup was not found
var_restore() {
  if [[ ! -f "${ENV_FILE_BACKUP}" ]]; then
    logError "Backup file does not exist: ${ENV_FILE_BACKUP}"
    return 1
  fi

  # Source the backup file to restore the shell variables
  source "${ENV_FILE_BACKUP}" 2&> /dev/null # Hide complaints about readonly variables
  logInfo "Shell variables have been restored from: ${ENV_FILE_BACKUP}"

  return 0
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
  local prop="$1"   # export property to insert
  local val="$2"    # the desired value

  if grep -q "^export ${prop}=" "${rcFile}"; then
    sed -i "s,^export ${prop}=.*$,export ${prop}=${val}," "${rcFile}"
    logInfo "[updated] export ${prop}=${val}"
  else
    echo -e "export ${prop}=${val}" >> "${rcFile}"
    logInfo "[inserted] export ${prop}=${val}"
  fi

  # shellcheck source=../../.bashrc
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

###########################
###### Startup logic ######
###########################

EV_ARGS=("$@")
EV_CWD=$(pwd)
EV_ME="$(basename "$0")"

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

# Import dependencies
source ${EV_ROOT}/src/slf4sh.sh

if [[ -p /dev/stdin ]]; then
  # This script was piped
  echo "ERROR: This script cannot be piped"
  exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  echo "ERROR: This script cannot be executed"
  exit 1
fi