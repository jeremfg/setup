#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script is used to manipulate dotenv configuration files

if [[ -z ${GUARD_CONFIG_SH} ]]; then
  GUARD_CONFIG_SH=1
else
  return
fi

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
    local _content
    # The file might be encrypted
    if sops --input-type dotenv --output-type dotenv -d "${_config_file}" &> /dev/null; then
      _content=$(sops --input-type dotenv --output-type dotenv -d "${_config_file}")
      logInfo "Read from encrypted ${_config_file}"
    else
      _content=$(cat "${_config_file}")
      logInfo "Read from ${_config_file}"
    fi
    # Parse special value @GIT_ROOT@
    if grep -q "@GIT_ROOT@" <<<"${_content}"; then
      # We need git root to replace @GIT_ROOT@ in _content
      source ${CF_ROOT}/src/git.sh
      local git_root
      if ! git_find_root git_root "${CF_ROOT}"; then
        logError "Failed to find the root of the repository, required by ${_config_file}"
        return 1
      fi
      _content="${_content//"@GIT_ROOT@"/${git_root}}"
    fi
    logDebug <<EOF
Loading the following:

${_content}
EOF
    source <(echo "${_content}")
    return 0
  else
    logError "Configuration file not found: ${_config_file}"
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

  # Check if the file is encrypted
  if sops --input-type dotenv --output-type dotenv -d "${_config_file}" &> /dev/null; then
    # File is encrypted, decrypt it to a variable
    _content=$(sops --input-type dotenv --output-type dotenv -d "${_config_file}")
  else
    # File is not encrypted, read it into a variable
    _content=$(cat "${_config_file}")
  fi

  # If no value is provided, delete the configuration
  if [[ -z "${_value}" ]]; then
    logInfo "Deleting configuration: ${_config}"
    if grep -q "^${_config}=" <<<"${_content}"; then
      _content=$(echo "${_content}" | sed "/^${_config}=.*/d")
    else
      logWarn "Configuration does not exist: ${_config}"
      return 0
    fi
    if [[ $? -ne 0 ]]; then
      logError "Failed to delete configuration: ${_config}"
      return 1
    fi
  else
    # If value contains spaces, wrap it in quotes
    if [[ "${_value}" == *" "* ]]; then
      _value="\"${_value}\""
    fi

    # Add or update the config in _content
    if grep -q "^${_config}=" <<<"${_content}"; then
      logInfo "Updating configuration: ${_config}"
      _content=$(echo "${_content}" | sed "s|^${_config}=.*|${_config}=${_value}|")
      if [[ $? -ne 0 ]]; then
        logError "Failed to update configuration: ${_config}"
        return 1
      fi
    else
      logInfo "Adding configuration: ${_config}"
      _content=$(echo -e "${_content}\n${_config}=${_value}")
      if [[ $? -ne 0 ]]; then
        logError "Failed to add configuration: ${_config}"
        return 1
      fi
    fi
  fi

  # Save configuration to config file
  if [[ -f  "${_config_file}" ]]; then
    if sops --input-type dotenv --output-type dotenv -d "${_config_file}" &> /dev/null; then
       echo "${_content}" | sops --input-type dotenv --output-type dotenv -e /dev/stdin > "${_config_file}"
      if [[ $? -ne 0 ]]; then
        logError "Failed to write encrypted configuration"
        return 1
      fi
      logInfo "Settings saved encrypted into ${_config_file}"
    else
      echo "${_content}" > "${_config_file}"
      if [[ $? -ne 0 ]]; then
        logError "Failed to write configuration"
        return 1
      fi
      logInfo "Settings saved into ${_config_file}"
    fi
  else
    if ! mkdir -p "$(dirname "${_config_file}")"; then
      logError "Failed to create directory: $(dirname "${_config_file}")"
      return 1
    fi
    # Do not encrypt by default
    echo "${_content}" > "${_config_file}"
    if [[ $? -ne 0 ]]; then
      logError "Failed to write configuration"
      return 1
    fi
    logInfo "Settings saved into newly created ${_config_file}"
  fi

  return 0
}

###########################
###### Startup logic ######
###########################
CF_ARGS=("$@")
CF_CWD=$(pwd)
CF_ME="$(basename "${BASH_SOURCE[0]}")"

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
