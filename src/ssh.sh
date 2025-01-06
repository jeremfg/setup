# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# SSH confiuration utilities

if [[ -z ${GUARD_SSH_SH} ]]; then
  GUARD_SSH_SH=1
else
  return 0
fi

# Test connection to SSH server, making sure credentials are good
#
# Parameters:
#   $1[in]: Url to test
# Returns:
#   0: Connection successful
#   1: Bad credentials
#   2: Other error
ssh_test_connection() {
  sg_ssh_test_connection "${1}"
  return $?
}

ssh_agent_install() {
  # Check if we have ssh support
  if ! command -v ssh &>/dev/null; then
    logError "ssh not found"
    return 1
  fi
  if ! command -v ssh-agent &>/dev/null; then
    logError "ssh-agent not found"
    return 1
  fi
  if ! command -v ssh-add &>/dev/null; then
    logError "ssh-add not found"
    return 1
  fi
  if ! command -v ssh-keygen &>/dev/null; then
    logError "ssh-add not found"
    return 1
  fi
  if [[ -z "${CONFIG_DIR}" ]]; then
    logError "CONFIG_DIR is not set"
    return 1
  fi

  local config_filename
  config_filename="${CONFIG_DIR}/${SSH_INIT_FILE}"

  # Only create the file if it doesn't exist already
  if [[ ! -f "${config_filename}" ]]; then
    local file
    file=$(
      cat <<EOF
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# SSH confiuration to be invoked at startup
# (This file was automatically generated)

# Make sure the ssh-agent is running
# Recipe from: https://rabexc.org/posts/pitfalls-of-ssh-agents
ssh-add -l &>/dev/null
if [[ "\$?" == 2 ]]; then
  test -r ~/.ssh-agent && eval "\$(<~/.ssh-agent)" >/dev/null
  ssh-add -l &>/dev/null
  if [[ "\$?" == 2 ]]; then
    (umask 066; ssh-agent > ~/.ssh-agent)
    eval "\$(<~/.ssh-agent)" >/dev/null
    ssh-add
  fi
fi

# Below are keys to be supported
EOF
    )

    logInfo "Creating SSH configuration file: ${config_filename}"
    mkdir -p "$(dirname "${config_filename}")"
    echo "${file}" >"${config_filename}"
  else
    logInfo "SSH configuration already present"
  fi

  # Add to .bashrc
  file="source ${config_filename}"
  if ! env_config "${file}"; then
    logError "Failed to configure init script for ssh-agent"
    return 1
  fi

  return 0
}

# Install a key at init
#
# Parameters:
#   $1[in]: Path to key
ssh_key_install() {
  local key="${1}"

  if [[ -z "${CONFIG_DIR}" ]]; then
    logError "CONFIG_DIR is not set"
    return 1
  fi

  local config_filename
  config_filename="${CONFIG_DIR}/${SSH_INIT_FILE}"

  # Build configuration line
  local cf_line
  cf_line="ssh-add ${key} > /dev/null 2>&1"

  if [[ ! -f "${config_filename}" ]]; then
    if ! ssh_agent_install; then
      logError "Could not prepare the configuration file"
    fi
  fi

  # Is configuration already existing?
  if ! grep -q "^${cf_line}\$" "${config_filename}"; then
    if ! echo "${cf_line}" >>"${config_filename}"; then
      logError "Failed to insert ssh key in configuration"
      return 1
    fi
  else
    logInfo "SSH key already configured"
  fi

  # Load key immediately as well
  eval "${cf_line}"

  return 0
}

# Returns the next key filename to use
#
# Parameters:
#   $1[out]: Filename for the key
#   $2[in]:  Prefix for the filename
# Returns:
#   0: If a filename was generated
ssh_next_key_name() {
  local _filename="$1"
  local prefix="$2"

  # Find an available filename
  local myfile
  local i=0
  while [[ -f "${SSH_DIR}/${prefix}_${i}" ]]; do
    ((i++))
  done
  myfile="${SSH_DIR}/${prefix}_${i}"
  logInfo "Filename generation: ${myfile}"
  touch "${myfile}"
  eval "${_filename}='${myfile}'"
  rm -f "${myfile}"
  return 0
}

# Ask user for which private key to use
#
# Parameters:
#   $1[out]: Absolute path to the private key
#   $2[in]:  Absolute path to the key, if one needs to be generated
# Returns:
#   0: If a key was selected (See $1)
#   1: If an error occured, and we must proceed without a key
ssh_ask() {
  local private_key="$1"
  local suggested_key="$2"

  if [[ ! -d "${SSH_DIR}" ]]; then
    logInfo "Creating SSH directory: ${SSH_DIR}"
    if ! mkdir -p "${SSH_DIR}"; then
      logError "Failed to create SSH directory"
      return 1
    fi
  fi

  # List all files in the .ssh dir
  local ssh_files=()
  local ssh_file
  for ssh_file in "${SSH_DIR}"/*; do
    if [[ $(basename "${ssh_file}") == "authorized_keys" ]]; then
      : # Skip this file
    elif [[ $(basename "${ssh_file}") == "known_hosts" ]]; then
      : # Skip this file
    elif [[ $(basename "${ssh_file}") == "config" ]]; then
      : # Skip this file
    elif [[ $(basename "${ssh_file}") == *.pub ]]; then
      : # Skip files with .pub extension
    elif [[ -f "${ssh_file}" ]]; then
      ssh_files+=("${ssh_file}")
    else
      logWarn "Skipped unrecognized entry: ${ssh_file}"
    fi
  done

  # Build the list of options
  local options=()
  options+=("Abort and exit")
  options+=("Generate a new SSH key")
  options+=("Paste an existing SSH private key")
  for ssh_file in "${ssh_files[@]}"; do
    options+=("Use existing private key: ${ssh_file}")
  done

  # Print the question
  cat <<EOF
******************************
**** SSH Key configurator ****
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
    return 2
    ;;
  2)
    logInfo "User chose to generate a new SSH key"
    # Ask user for his email address
    if ssh_generate_keypair "${suggested_key}"; then
      eval "${private_key}='${suggested_key}'"
      return 0
    else
      return 1
    fi
    ;;
  3)
    logInfo "User chose to paste an existing SSH private key"
    # Ask user for key, read input and write to file
    if ssh_paste_key "${suggested_key}"; then
      eval "${private_key}='${suggested_key}'"
      return 0
    else
      return 1
    fi
    ;;
  *)
    local ssh_file="${ssh_files[$((choice - 4))]}"
    if ! chmod 0600 "${ssh_file}"; then
      logError "Failed to change permissions on key file"
    fi
    logInfo "User chose to use existing private key: ${ssh_file}"
    eval "${private_key}='${ssh_file}'"
    return 0
    ;;
  esac
}

# Guide the user in generating a new keypair
#
# Parameters:
#   $1[in]: Absolute path where the key will be stored
# Returns:
#   0: If a key was generated
#   1: If an error occured, and we must proceed without a key
ssh_generate_keypair() {
  local _prv_key="$1"
  local file
  local email
  local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"

  # Ask for email address
  os_ask_user email "Your email address" "" 65535
  if [[ -z "${email}" ]]; then
    echo "Error: Email address cannot be empty" >&2
    return 1
  fi

  # Check with regex it's a valid email
  if [[ "${email}" =~ ${regex} ]]; then
    logInfo "Generating SSH key: ${file}"

    if ! ssh-keygen -t ed25519 -C "${email}" -f "${_prv_key}"; then
      logError "Failed to generate SSH key"
      return 1
    else
      cat <<EOF
******************************************************
Your new private key was generated in: ${_prv_key}
You will now need to configure your public key so your identify will be accepted by the git server.
For github, follow the instructions here: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account?tool=webui

Below is what you will need to paste:
---------------------------------
$(cat "${_prv_key}.pub" || true)
---------------------------------
Press [Enter] when you are done registering your key
EOF
      # Wait for user to press Enter
      # shellcheck disable=SC2162
      read </dev/tty
    fi
  else
    echo "Error: This is not a valid email address" >&2
    return 1 # Invalid email
  fi

  return 0
}

# Ask user to paste his private key
#
# Parameters:
#   $1[in]: Absolute path where the key will be stored
# Returns:
#   0: If a key was generated
#   1: If an error occured, and we must proceed without a key
ssh_paste_key() {
  sg_ssh_paste_key "${1}"
  return $?
}

# Constants
SSH_INIT_FILE="ssh_init.sh"
SSH_DIR="${HOME}/.ssh"

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
SS_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${SS_SOURCE}" ]]; do # resolve $SS_SOURCE until the file is no longer a symlink
  SS_ROOT=$(cd -P "$(dirname "${SS_SOURCE}")" >/dev/null 2>&1 && pwd)
  SS_SOURCE=$(readlink "${SS_SOURCE}")
  [[ ${SS_SOURCE} != /* ]] && SS_SOURCE=${SS_ROOT}/${SS_SOURCE} # if $SS_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SS_ROOT=$(cd -P "$(dirname "${SS_SOURCE}")" >/dev/null 2>&1 && pwd)
SS_ROOT=$(realpath "${SS_ROOT}/..")

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
if ! source "${SS_ROOT}/src/env.sh"; then
  logFatal "Failed to import env.sh"
fi
if ! source "${SS_ROOT}/src/os.sh"; then
  logFatal "Failed to import os.sh"
fi
if ! source "${SS_ROOT}/src/setup_git"; then
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
