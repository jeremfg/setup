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

# Retrieve the next filename in a sequence
#
# Parameters:
#   $1[out]: New filename
#   $2[in]: Desired filename
os_get_next_filename() {
  local _new="$1"
  local _desired="$2"
  local res

  local ext="${_desired##*.}"
  local base="${_desired%.*}"
  local -i nb
  res="${base}.${ext}"
  while [[ -f "${res}" ]]; do
    if [[ -z "${nb}" ]]; then
      nb=0
    else
      nb=$((nb + 1))
    fi
    res="${base}_${nb}.${ext}"
  done

  logInfo "Next filename: ${res}"
  eval "${_new}='${res}'"
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

# Add a configuration line to the specified file
#
# Parameters:
#   $1[in]: Configuration file
#   $2[in]: Configuration line
# Returns:
#   0: Success
#   1: Failure
os_add_config() {
  local cfg_file="$1"
  local cfg_line="$2"

  if [[ -z "${cfg_line}" ]]; then
    logError "Cannot configure an empty line"
    return 1
  fi

  if [[ -f "${cfg_file}" ]]; then
    if ! grep -q "^${cfg_line}\$" "${cfg_file}"; then
      # Configuration line is absent. Add it
      if ! echo "${cfg_line}" >>"${cfg_file}"; then
        logError "Failed to insert line in configuration: ${cfg_line}"
        return 1
      fi
    else
      logInfo "Configuration line already present: ${cfg_line}"
    fi
  else
    echo "${cfg_line}" >"${cfg_file}"
    logInfo "Created configuration file: ${cfg_file} and added line: ${cfg_line}"
  fi

  return 0
}

os_rm_config() {
  local cfg_file="$1"
  local cfg_line="$2"

  if [[ -z "${cfg_line}" ]]; then
    logError "Cannot remove an empty line"
    return 1
  fi

  if [[ -f "${cfg_file}" ]]; then
    if grep -q "^${cfg_line}\$" "${cfg_file}"; then
      # Configuration line is present. Remove it
      if ! sed -i "/^${cfg_line}$/d" "${cfg_file}"; then
        logError "Failed to remove line in configuration: ${cfg_line}"
        return 1
      fi
    else
      logInfo "Configuration line not present: ${cfg_line}"
    fi
  else
    logWarn "Configuration file not found: ${cfg_file}"
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
fi
if ! source "${OS_ROOT}/src/setup_git"; then
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
