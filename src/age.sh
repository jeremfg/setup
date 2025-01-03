# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure AGE

if [[ -z ${GUARD_AGE_SH} ]]; then
  GUARD_AGE_SH=1
else
  return 0
fi

# Install AGE (if not already installed)
#
# Parameters:
age_install() {
  if command -v age &>/dev/null; then
    logInfo "AGE is already installed"
    return 0
  fi
  if [[ -z "${DOWNLOAD_DIR}" ]]; then
    logError "DOWNLOAD_DIR is not set"
    return 1
  fi
  if [[ -z "${BIN_DIR}" ]]; then
    logError "BIN_DIR is not set"
    return 1
  fi

  local url installer location=
  url="${AGE_URL}"
  installer="$(basename "${url}")"
  location="${DOWNLOAD_DIR}/${installer}"

  if [[ ! -f "${location}" ]]; then
    if ! mkdir -p "$(dirname "${location}")"; then
      logError "Failed to create directory for AGE archive"
      return 1
    fi
    logTrace "Downloading into ${location} from ${url}"
    if ! curl -sSL -o "${location}" "${url}"; then
      logError "Failed to download age archive"
      return 1
    fi
  fi
  if ! tar -xvf "${location}" -C "${BIN_DIR}"; then
    logFatal "Failed to extract age"
  fi

  # For all binary files create a simlink in the bin directory
  local binfile sim_file
  for binfile in "${BIN_DIR}/age"/*; do
    if [[ -x "${binfile}" ]]; then
      sim_file="${HOME}/bin/$(basename "${binfile}")"
      if ! mkdir -p "${HOME}/bin"; then
        logError "Failed to create directory for binaries"
        return 1
      fi
      if [[ ! -L "${sim_file}" ]]; then
        logTrace "Creating symlink: ${sim_file}"
        if ! ln -s "${binfile}" "${sim_file}"; then
          logError "Failed to create symlink"
          return 1
        fi
      fi
    fi
  done

  # Confirm age is working
  if ! command -v age &>/dev/null; then
    logError "Failed to install AGE"
    return 1
  else
    logInfo "AGE installation detected"
    return 0
  fi
}

# Configure the AGE key
#
# Parameters:
#   $1[in]: key name
# Returns:
#   0: If key is configured
#   1: If we couldn't configure the key
age_configure() {
  local key_name="${1}"
  local key_dir="${HOME}/.sops"
  local key="${key_dir}/${key_name}.txt"
  if [[ ! -f "${key}" ]]; then
    logInfo "Key not found: ${key}"
    if ! mkdir -p "${key_dir}"; then
      logError "Failed to create directory for keys"
      return 1
    fi
    local key_files=()
    local key_file
    for key_file in "${key_dir}"/*; do
      # FIlter on txt extension
      if [[ "${key_file}" == *.txt ]]; then
        key_files+=("${key_file}")
      fi
    done

    # Build the list of options
    local options=()
    options+=("Abort and exit")
    options+=("Generate a new AGE key")
    options+=("Paste an existing AGE key")
    for key_file in "${key_files[@]}"; do
      options+=("Copy existing key: ${key_file}")
    done

    # Print the question
    cat <<EOF
******************************
**** AGE Key configurator ****
******************************
Please select one of the options below:
EOF

    for i in "${!options[@]}"; do
      echo "  $((i + 1)). ${options[${i}]}"
    done

    # Read user input
    local choice
    while true; do
      read -rp "Enter the number of your choice: " choice </dev/tty
      if [[ "${choice}" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
        logInfo "User chose option ${choice}: ${options[choice - 1]}"
        break
      else
        echo "Invalid choice. Please try again."
      fi
    done

    # Process user choice
    case ${choice} in
    1)
      logInfo "User chose to abort"
      return 1
      ;;
    2)
      logInfo "User chose to generate a new SSH key"
      if ! age-keygen -o "${key}"; then
        logFatal "Failed to generate a new encryption key"
      else
        logTrace "Key generation succeeded"
      fi
      ;;
    3)
      logInfo "User chose to paste an existing SSH private key"
      cat <<EOF
======================================
========== AGE key required ==========
======================================
1. Please paste the age key below.
2. Press [Enter] to end on a new line.
3. Press Ctrl+D to finish.
______________________________________
EOF

      # Read in the private key from /dev/tty
      local key_content
      key_content=$(cat /dev/tty)
      echo "${key_content}" >"${key}"
      cat <<EOF
______________________________________
EOF
      chmod 600 "${key}"
      ;;
    *)
      key_file="${key_files[$((choice - 4))]}"
      logInfo "User chose to use existing age key: ${key_file}"
      if cp "${key_file}" "${key}"; then
        logTrace "Key copied successfully"
      else
        logError "Failed to copy key"
        return 1
      fi
      ;;
    esac
  fi
  if ! env_add "SOPS_AGE_KEY_FILE" "${key}"; then
    logError "Failed to configure AGE key"
    return 1
  fi

  # Confirm we have a key
  if [[ -f "${key}" ]]; then
    logInfo "AGE key configured"
    return 0
  else
    logError "Failed to configure AGE key"
    return 1
  fi
}

# Constants

AGE_VERSION="1.2.0"
AGE_URL="https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz"

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
AG_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${AG_SOURCE}" ]]; do # resolve $AG_SOURCE until the file is no longer a symlink
  AG_ROOT=$(cd -P "$(dirname "${AG_SOURCE}")" >/dev/null 2>&1 && pwd)
  AG_SOURCE=$(readlink "${AG_SOURCE}")
  [[ ${AG_SOURCE} != /* ]] && AG_SOURCE=${AG_ROOT}/${AG_SOURCE} # if $AG_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
AG_ROOT=$(cd -P "$(dirname "${AG_SOURCE}")" >/dev/null 2>&1 && pwd)
AG_ROOT=$(realpath "${AG_ROOT}/..")

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
if ! source "${AG_ROOT}/src/git.sh"; then
  logFatal "Failed to import git.sh"
fi
if ! source "${AG_ROOT}/src/env.sh"; then
  logFatal "Failed to import env.sh"
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
