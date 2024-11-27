#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script is used to manipulate dotenv configuration files

# Load all configurations from specified file
#
# Parameters:
#   $1[in]: Configuration file
# Returns:
#   0: Success
#   1: Configuration file not found
config_load() {
  local _config_file="$1"
  if [[ -f "${_config_file}" ]]; then
    # shellcheck source=.config/project-config.env
    source "${_config_file}"
    echo "Settings loaded from --> ${_config_file}"
    return 0
  else
    echo "Configuration file not found: ${_config_file}"
    return 1
  fi
}

# Persist a configuration to a specified file
#
# Parameters:
#   $1[in]: Configuration file
#   $2[in]: Configuration key
#   $3[in]: Configuration value
# Returns:
#   0: Success
#   1: Failure
config_save() {
  local _config_file="$1"
  local _config="$2"
  local _value="$3"

  # Validate all parameters
  if [[ -z "${_config_file}" ]]; then
    logError "Configuration file not provided"
    return 1
  fi
  if [[ -z "${_config}" ]]; then
    logError "Configuration key not provided"
    return 1
  fi

  # Config cannot contain spaces
  if [[ "${_config}" == *" "* ]]; then
    logError "Configuration key cannot contain spaces"
    return 1
  fi

  # If no value is provided, delete the configuration
  if [[ -z "${_value}" ]]; then
    if ! sed -i "/^${_config}=/d" "${_config_file}"; then
      logError "Failed to delete configuration: ${_config}"
      return 1
    fi
    return 0
  fi

  # If value contains spaces, wrap it in quotes
  if [[ "${_value}" == *" "* ]]; then
    _value="\"${_value}\""
  fi

  # Save configuration to config file
  if [[ -f "${_config_file}" ]]; then
    if grep -q "${_config}=" "${_config_file}"; then
      if ! sed -i "s|${_config}=.*|${_config}=${_value}|" "${_config_file}"; then
        logError "Failed to update configuration: ${_config}"
        return 1
      fi
    else
      if ! echo "${_config}=${_value}" >>"${_config_file}"; then
        logError "Failed to add configuration: ${_config}"
        return 1
      fi
    fi
  else
    if ! mkdir -p "$(dirname "${_config_file}")"; then
      logError "Failed to create directory: $(dirname "${_config_file}")"
      return 1
    fi
    echo "${_config}=${_value}" >"${_config_file}"
  fi
  logInfo "Settings saved into --> ${_config_file}"
  return 0
}

###########################
###### Startup logic ######
###########################
CF_ARGS=("$@")
CF_CWD=$(pwd)
CF_ME="$(basename "$0")"

# Get directory of this script
# https://stackoverflow.com/a/246128
CF_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${CF_SOURCE}" ]]; do # resolve $CF_SOURCE until the file is no longer a symlink
  CF_ROOT=$(cd -P "$(dirname "${CF_SOURCE}")" >/dev/null 2>&1 && pwd)
  CF_SOURCE=$(readlink "${CF_SOURCE}")
  [[ ${CF_SOURCE} != /* ]] && CF_SOURCE=${CF_ROOT}/${CF_SOURCE} # if $CF_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
CF_ROOT=$(cd -P "$(dirname "${CF_SOURCE}")" >/dev/null 2>&1 && pwd)
CF_ROOT=$(realpath "${CF_ROOT}/..")

# Import dependencies
source ${CF_ROOT}/src/slf4sh.sh

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
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
