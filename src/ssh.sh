# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# SSH configuration utilities

if [[ -z ${GUARD_SSH_SH+x} ]]; then
  GUARD_SSH_SH=1
else
  logWarn "Re-sourcing ssh.sh"
  return 0
fi

ssh_server_install() {
  if ! pkg_install openssh-server; then
    logError "Failed to install openssh-server"
    return 1
  fi

  local res
  res=$(sudo systemctl status ssh 2>&1)

  # Enable the service if it's not active
  if [[ "${res}" = *"inactive"* ]]; then
    logInfo "Enabling ssh service"
    if ! sudo systemctl enable --now ssh; then
      logError "Failed to enable ssh service"
      return 1
    fi
  else
    logInfo "ssh service is already active"
  fi

  # Make sure the service is running
  res=$(sudo systemctl status ssh 2>&1)
  if [[ "${res}" != *"active (running)"* ]]; then
    logError "ssh service is not running"
    if ! sudo systemctl start ssh; then
      logError "Failed to start ssh service"
      return 1
    fi
  else
    logInfo "ssh service is already running"
  fi

  # Test again that SSH is running
  if ! res=$(sudo systemctl status ssh 2>&1); then
    logError "Failed to check if ssh service is running: ${res}"
    return 1
  fi
  if [[ "${res}" != *"active (running)"* ]]; then
    logError "ssh service is not running after starting it"
    return 1
  fi

  logInfo "ssh service is running"

  # Print config of the service
  logInfo <<EOF
SSH Service Configuration:
$(cat /etc/ssh/sshd_config || true)
EOF

  # Make sure firewall allows SSH
  if ! sudo ufw allow ssh; then
    logError "Failed to allow ssh through the firewall"
    return 1
  fi
  if ! sudo ufw enable; then
    logError "Failed to enable firewall"
    return 1
  fi

  return 0
}

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
  elif ! command -v ssh-agent &>/dev/null; then
    logError "ssh-agent not found"
    return 1
  elif ! command -v ssh-add &>/dev/null; then
    logError "ssh-add not found"
    return 1
  elif ! command -v ssh-keygen &>/dev/null; then
    logError "ssh-add not found"
    return 1
  elif [[ -z "${CONFIG_DIR}" ]]; then
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
# SSH configuration to be invoked at startup
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
    if ! file_ensure_dir "$(dirname "${config_filename}")"; then
      logError "Failed to create directory for SSH configuration"
      return 1
    fi
    echo "${file}" >"${config_filename}"
  else
    logInfo "SSH configuration already present"
  fi

  # Add to .bashrc
  file="source ${config_filename}"
  # shellcheck disable=SC1090
  if ! env_config "${file}"; then
    logError "Failed to configure init script for ssh-agent"
    return 1
  elif ! source "${config_filename}"; then
    # Start the agent in the current session
    logError "Failed to start ssh-agent in current session"
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

  if ! file_config_add "${config_filename}" "${cf_line}"; then
    logError "Failed to insert ssh key in configuration"
    return 1
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
  while [[ -f "${HOME}/${SSH_DIR_REL}/${prefix}_${i}" ]]; do
    ((i++))
  done
  myfile="${HOME}/${SSH_DIR_REL}/${prefix}_${i}"
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
#   1: If an error occurred, and we must proceed without a key
ssh_ask() {
  local private_key="$1"
  local suggested_key="$2"

  if [[ ! -d "${HOME}/${SSH_DIR_REL}" ]]; then
    logInfo "Creating SSH directory: ${HOME}/${SSH_DIR_REL}"
    if ! file_ensure_dir "${HOME}/${SSH_DIR_REL}"; then
      logError "Failed to create SSH directory"
      return 1
    fi
  fi

  # List all files in the .ssh dir
  local ssh_files=()
  local ssh_file
  for ssh_file in "${HOME}/${SSH_DIR_REL}"/*; do
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

  # Make sure the destination folder exists
  if ! file_ensure_dir "$(dirname "${suggested_key}")"; then
    logError "Failed to create directory for key"
    return 1
  fi

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
    if ! file_secure "${ssh_file}"; then
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
#   1: If an error occurred, and we must proceed without a key
ssh_generate_keypair() {
  local _prv_key="$1"
  local file
  local email
  local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"

  # Ask for email address
  os_ask_user email "Your email address" "" "${SSH_USER_INPUT_TIMEOUT}"
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
#   1: If an error occurred, and we must proceed without a key
ssh_paste_key() {
  sg_ssh_paste_key "${1}"
  return $?
}

# Create an identity remotely or locally
#
# Parameters:
#   $1[out]: The public key created
#   $2[in]:  The username (Omit if creating locally)
#   $3[in]:  The password (Omit if creating locally)
#   $4[in]:  The host (Omit if creating locally)
#   $5[in]:  The port (Omit if creating locally)
# Returns:
#   0: If the identity was created
#   1: If an error occurred
ssh_identity_create() {
  local __ssh_pub_key="${1}"
  local __ssh_user="${2}"
  local __ssh_pwd="${3}"
  local __ssh_host="${4}"
  local __ssh_port="${5}"

  local _id_cmd _id_res _id_code
  # Try to read the public key if it exists
  # shellcheck disable=SC2088
  _id_cmd=(test -e "~/${SSH_IDENTITY_PUB_KEY_REL}")
  if [[ -z ${__ssh_host} ]]; then
    _id_res=$("${_id_cmd[@]}" 2>&1)
    _id_code=$?
  else
    ssh_exec _id_res "${__ssh_user}" "${__ssh_pwd}" "${__ssh_host}" "${__ssh_port}" "${_id_cmd[@]}"
    _id_code=$?
    if [[ ${_id_code} -eq 201 ]]; then
      _id_code=1 # No file, but connection was successful
    elif [[ ${_id_code} -eq 1 ]]; then
      logError "Failed to check for existing identity: ${_id_res}"
      return 1
    fi
  fi
  if [[ ${_id_code} -eq 0 ]]; then
    logInfo "Identity already exists"
    # shellcheck disable=SC2088
    _id_cmd=(cat "~/${SSH_IDENTITY_PUB_KEY_REL}")
    if [[ -z ${__ssh_host} ]]; then
      _id_res=$("${_id_cmd[@]}" 2>&1)
      _id_code=$?
    else
      ssh_exec _id_res "${__ssh_user}" "${__ssh_pwd}" "${__ssh_host}" "${__ssh_port}" "${_id_cmd[@]}"
      _id_code=$?
    fi
    if [[ ${_id_code} -ne 0 ]]; then
      logError "Failed to read public key"
      return 1
    fi
    eval "${__ssh_pub_key}='${_id_res}'"
    return 0
  elif [[ ${_id_code} -eq 1 ]]; then
    logInfo "Creating identity"
    # shellcheck disable=SC2088
    _id_cmd=(ssh-keygen -t ed25519 -f "~/${SSH_IDENTITY_KEY_REL}" -N)
    if [[ -z ${__ssh_host} ]]; then
      _id_cmd+=("")
      _id_res=$("${_id_cmd[@]}" 2>&1)
      _id_code=$?
    else
      _id_cmd+=("\"\"")
      ssh_exec _id_res "${__ssh_user}" "${__ssh_pwd}" "${__ssh_host}" "${__ssh_port}" "${_id_cmd[@]}"
      _id_code=$?
    fi
    if [[ ${_id_code} -ne 0 ]]; then
      logError "Failed to create identity: ${_id_code}"
      return 1
    fi
    # shellcheck disable=SC2088
    _id_cmd=(cat "~/${SSH_IDENTITY_PUB_KEY_REL}")
    if [[ -z ${__ssh_host} ]]; then
      _id_res=$("${_id_cmd[@]}" 2>&1)
      _id_code=$?
    else
      ssh_exec _id_res "${__ssh_user}" "${__ssh_pwd}" "${__ssh_host}" "${__ssh_port}" "${_id_cmd[@]}"
      _id_code=$?
    fi
    if [[ ${_id_code} -ne 0 ]]; then
      logError "Failed to read public key"
      return 1
    fi
    eval "${__ssh_pub_key}='${_id_res}'"
    return 0
  else
    logError "Failed to check for identity: ${_id_code}"
    return 1
  fi
}

# Remotely authorize an identity
#
# Parameters:
#   $1[in]: The public key to authorize
#   $2[in]: The username (If omitted, current user will be assumed)
#   $3[in]: The password (Omit if authorizing locally)
#   $4[in]: The host (Omit if authorizing locally)
#   $5[in]: The port (Omit if authorizing locally)
# Returns:
#   0: If the identity was authorized
#   1: If an error occurred
ssh_identity_authorize() {
  local __ssh_pub_key="${1}"
  local __ssh_user="${2}"
  local __ssh_pwd="${3}"
  local __ssh_host="${4}"
  local __ssh_port="${5}"

  local _auth_cmd _auth_res _auth_code _homedir _auth_file _need_sudo
  _need_sudo=0
  # First, determine the home directory of the user
  if [[ -z "${__ssh_host}" ]] && [[ -n "${__ssh_user}" ]]; then
    if ! _homedir=$(getent passwd "${__ssh_user}"); then
      logError "Failed to get home directory of user ${__ssh_user}"
      return 1
    else
      _homedir=$(echo "${_homedir}" | cut -d: -f6)
    fi
    if [[ "$(id -u "${__ssh_user}" || true)" != "$(id -u || true)" ]]; then
      logWarn "Authorizing key for a different user (${__ssh_user}). This will require elevated permissions."
      _need_sudo=1
    fi
  else
    _homedir="~"
  fi
  _auth_file="${_homedir}/${SSH_DIR_REL}/authorized_keys"

  # Second, check if the key is already authorized
  _auth_cmd=()
  if [[ ${_need_sudo} -eq 1 ]]; then
    _auth_cmd+=(sudo)
  fi
  _auth_cmd+=(grep -Fqx "${__ssh_pub_key}" "${_auth_file}")
  if [[ -z ${__ssh_host} ]]; then
    _auth_res=$("${_auth_cmd[@]}" 2>&1)
    _auth_code=$?
  else
    ssh_exec _auth_res "${__ssh_user}" "${__ssh_pwd}" "${__ssh_host}" "${__ssh_port}" "${_auth_cmd[@]}"
    _auth_code=$?
    if [[ ${_auth_code} -eq 201 ]]; then
      _auth_code=1 # Error code was remote, not local
    elif [[ ${_auth_code} -eq 1 ]]; then
      logError "Failed to check for existing identity: ${_auth_res}"
      return 1
    fi
  fi
  if [[ ${_auth_code} -eq 0 ]]; then
    logInfo "Identity already authorized"
    return 0
  elif [[ ${_auth_code} -eq 1 ]]; then
    logInfo "Identity not present. Adding it..."
    _auth_cmd=()
    if [[ ${_need_sudo} -eq 1 ]]; then
      _auth_cmd+=(sudo)
    fi
    _auth_cmd+=(sh -c "printf '%s\n' \"\${1}\" >> \"\${2}\"")
    _auth_cmd+=("--" "${__ssh_pub_key}" "${_auth_file}")
    if [[ -z ${__ssh_host} ]]; then
      _auth_res=$("${_auth_cmd[@]}" 2>&1)
      _auth_code=$?
    else
      ssh_exec _auth_res "${__ssh_user}" "${__ssh_pwd}" "${__ssh_host}" "${__ssh_port}" "${_auth_cmd[@]}"
      _auth_code=$?
    fi
    if [[ ${_auth_code} -ne 0 ]]; then
      logError "Failed to authorize identity"
      return 1
    fi
  else
    logError "Failed to check for identity (${_auth_code}): ${_auth_res}"
    return 1
  fi

  return 0
}

# Execute a command on a remote host via SSH
#
# Parameters:
#   $1[out]: The command output
#   $2[in]:  The username
#   $3[in]:  The password
#   $4[in]:  The host
#   $5[in]:  The port
#   $@[in]:  The command to execute
# Returns:
#   1: If an error occurred
#   $?: The return code of the command
ssh_exec() {
  local __ssh_output="${1}"
  local __ssh_user="${2}"
  local __ssh_pwd="${3}"
  local __ssh_host="${4}"
  local __ssh_port="${5}"
  shift 5

  # Validate inputs
  if ! command -v ssh &>/dev/null; then
    logError "ssh tool not found"
    return 1
  elif [[ -z ${__ssh_host} ]]; then
    logError "Host not specified"
    return 1
  elif [[ -n ${__ssh_port} ]] && [[ ! "${__ssh_port}" =~ ^[0-9]+$ ]]; then
    logError "Invalid port: ${__ssh_port}"
    return 1
  fi

  # Build the SSH command
  local _ssh_uri _ssh_cmd _ssh_res _ssh_code
  _ssh_cmd=(ssh -o "StrictHostKeyChecking=no")
  if [[ -n ${__ssh_port} ]]; then
    _ssh_cmd+=(-p "${__ssh_port}")
  fi
  _ssh_uri=""
  if [[ -n ${__ssh_user} ]]; then
    _ssh_uri+="${__ssh_user}@"
  fi
  _ssh_uri+="${__ssh_host}"
  _ssh_cmd+=("${_ssh_uri}")
  _ssh_cmd+=("$@")

  if [[ -n ${__ssh_pwd} ]]; then
    sshpass_exec _ssh_res "${__ssh_pwd}" "${_ssh_cmd[@]}"
    _ssh_code=$?
    # Filter post-quantum warning from output
    _ssh_res=$(echo "${_ssh_res}" | grep -v -e "post-quantum key exchange algorithm" -e "store now, decrypt later" -e "https://openssh.com/pq.html")
  else
    logTrace "Executing command: ${_ssh_cmd[*]}"
    _ssh_res=$("${_ssh_cmd[@]}" 2>&1)
    _ssh_code=$?
    # Filter post-quantum warning from output
    _ssh_res=$(echo "${_ssh_res}" | grep -v -e "post-quantum key exchange algorithm" -e "store now, decrypt later" -e "https://openssh.com/pq.html")

    if [[ ${_ssh_code} -ne 0 ]]; then
      logError <<EOF
Failed to Execute command: ${_ssh_cmd[*]}

Return Code: ${_ssh_code}
Output:
${_ssh_res}
EOF
    else
      logTrace "Command executed successfully${IFS}${_ssh_res}"
    fi
  fi

  # To distinguish between a failed command and a failed connection
  if [[ ${_ssh_code} -eq 201 ]]; then
    logWarn "It will be difficult to distinguish between a true error 201 and 1"
  elif [[ ${_ssh_code} -eq 1 ]]; then
    _ssh_code=201
  fi

  if [[ -n ${__ssh_output} ]]; then
    printf -v "${__ssh_output}" '%s' "${_ssh_res}"
  fi

  # shellcheck disable=SC2248
  return "${_ssh_code}"
}

# Execute a command that may require a SSH password
#
# Parameters:
#   $1[out]: The result of executing the command
#   $2[in]:  The password to use
#   $@[in]:  The command to execute
# Returns:
#   1: If an error occurred
#   $?: The return code of the command
sshpass_exec() {
  local __sshpass_output="${1}"
  local __sshpass_pwd="${2}"
  shift 2

  if ! command -v sshpass &>/dev/null; then
    logError "sshpass tool not found"
    return 1
  fi

  local _pass_cmd _pass_cmd_p _pass_res _pass_code
  _pass_cmd=()
  _pass_cmd_p=()
  if [[ -n ${__sshpass_pwd} ]]; then
    _pass_cmd+=(sshpass -p "${__sshpass_pwd}")
    _pass_cmd_p+=(sshpass -p "********")
  fi
  _pass_cmd+=("$@")
  _pass_cmd_p+=("$@")

  logTrace "Executing command: ${_pass_cmd_p[*]}"
  _pass_res=$("${_pass_cmd[@]}" 2>&1)
  _pass_code=$?
  # Filter post-quantum warning from output
  _pass_res=$(echo "${_pass_res}" | grep -v -e "post-quantum key exchange algorithm" -e "store now, decrypt later" -e "https://openssh.com/pq.html")

  if [[ ${_pass_code} -ne 0 ]]; then
    logError <<EOF
Failed to Execute command: ${_pass_cmd_p[*]}

Return Code: ${_pass_code}
Output:
${_pass_res}
EOF
  else
    logTrace "Command executed successfully${IFS}${_pass_res}"
  fi

  if [[ -n ${__sshpass_output} ]]; then
    printf -v "${__sshpass_output}" '%s' "${_pass_res}"
  fi

  # shellcheck disable=SC2248
  return "${_pass_code}"
}

# Global variables
SSH_INIT_FILE="ssh_init.sh"
SSH_DIR_REL=".ssh"
SSH_USER_INPUT_TIMEOUT=65535
SSH_IDENTITY_KEY_REL="${SSH_DIR_REL}/id_ed25519"
SSH_IDENTITY_PUB_KEY_REL="${SSH_IDENTITY_KEY_REL}.pub"

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
elif ! source "${SS_ROOT}/src/env.sh"; then
  logFatal "Failed to import env.sh"
elif ! source "${SS_ROOT}/src/os.sh"; then
  logFatal "Failed to import os.sh"
elif ! source "${SS_ROOT}/src/file.sh"; then
  logFatal "Failed to import file.sh"
elif ! source "${SS_ROOT}/src/setup_git"; then
  logFatal "Failed to import setup_git"
elif ! source "${SS_ROOT}/src/pkg.sh"; then
  logFatal "Failed to import pkg.sh"
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
