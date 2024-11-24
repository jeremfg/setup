#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure git

git_install() {
  if command -v git &> /dev/null; then
    logInfo "Git is already installed"
    return 0
  fi

  logInfo "Installing git..."
  if ! pkg_install "git"; then
    logError "Could not install git"
    return 1
  else
    if command -v git &> /dev/null; then
      return 0
    else
      logError "Could not detect git installation"
      return 1
    fi
  fi
}

# Configure git for SSH access. This is an interactive function
#
# Parameters:
#   $1[out] URL to the github service. If none provided, Github is assuenmd
# Returns:
#   0: If SSH access was succesfully configured
#   1: If SSH configuration failed
git_ssh_config() {
  local git_server="$1"
  if [[ -z "${git_server}" ]]; then
    logInfo "No git server specified, defaulting to github"
    # Default to Github
    git_server="git@github.com"
  fi

  # Check if we have ssh support
  if ! command -v ssh &> /dev/null; then
    logError "ssh not found"
    return 1
  fi
  if ! command -v ssh-agent &> /dev/null; then
    logError "ssh-agent not found"
    return 1
  fi
  if ! command -v ssh-add &> /dev/null; then
    logError "ssh-add not found"
    return 1
  fi
  if ! command -v ssh-keygen &> /dev/null; then
    logError "ssh-add not found"
    return 1
  fi

  # Make sure the SSH agent is running
  local ssh_agent_started
  if [[ -z "${SSH_AUTH_SOCK}" ]]; then
    logInfo "SSH agent not running. Starting it."
    if eval "$(ssh-agent -s)"; then
      logInfo "Started successfully"
    else
      logError "Failed to start SSH agent"
      return 1
    fi
    ssh_agent_started="true"
  else
    logInfo "SSH agent already running"
    ssh_agent_started=""
  fi

  # Loop until we get SSH access
  local res
  local res2
  local key
  while true; do
    res2=$(ssh -o StrictHostKeyChecking=no -T "${git_server}" 2>&1)
    res=$?
    if [[ ${res} -eq 255 ]]; then
      logInfo "SSH connexion denied: ${res2}"
      if [[ -n "${key}" ]]; then
        # We already tried a key previously, remove it from the ssh agent
        if ! ssh-add -d "${key}"; then
          logWarn "An error occured while trying to remove a useless key from the ssh agent"
        fi
      fi
      if ! git_ssh_ask key; then
        break;
      else
        logInfo "Using key: ${key}"
        if ! ssh-add "${key}"; then
          logError "An error occured while trying to reigster the SSH key"
          break;
        fi
      fi
    elif [[ ${res} -eq 1 ]]; then
      # Inspect the error message
      if [[ "${res2}" == *"You've successfully authenticated"* ]]; then
        logInfo "Recognized the github.com welcome message"
        res=0
        break;
      else
        logError "Unrecognized SSH connection message for res=1: ${res2}. Exiting."
        break;
      fi
    elif [[ ${res} -eq 0 ]]; then
      logInfo "Connection successful: ${res2}"
      break;
    else
      logError "Unkown SSH connection error: ${res} - ${res2}. Exiting."
      break;
    fi
  done

  if [[ $res -ne 0 ]]; then
    # In case of error, de-register the last key we tried
    if [[ -n "${key}" ]]; then
      if ! ssh-add -d "${key}"; then
        logWarn "An error occured while trying to remove a useless key from the ssh agent"
      fi
    fi
  fi

  # Cleanup before returning
  if [[ -n "${ssh_agent_started}" ]]; then
    logInfo "Stopping SSH agent"
    if ! ssh-agent -k; then
      logError "Failed to stop SSH agent"
    fi
  fi

  return ${res}
}

# Ask user for which private key to use
#
# Parameters:
#   $1[in]: Absolute path to the private key
# Returns:
#   0: If a key was selected (See $1)
#   1: If an error occured, and we must proceed without a key
git_ssh_ask() {
  local private_key="$1"
  local ssh_dir
  local selected_file
  ssh_dir="${HOME}/.ssh"
  if [[ ! -d "${ssh_dir}" ]]; then
    logInfo "Creating SSH directory: ${ssh_dir}"
    if ! mkdir -p "${ssh_dir}"; then
      logError "Failed to create SSH directory"
      return 1
    fi
  fi

  # List all files in the .ssh dir
  local ssh_files=()
  local ssh_file
  for ssh_file in "${ssh_dir}"/*; do
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
   echo "  $((i+1)). ${options[$i]}"
  done

  # Read user input
  local choice
  while true; do
    read -rp "Enter the number of your choice: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      logInfo "User chose option ${choice}: ${options[choice - 1]}"
      break;
    else
      echo "Invalid choice. Please try again."
    fi
  done

  # Process user choice
  case $choice in
    1)
      logInfo "User chose to abort"
      return 2
      ;;
    2)
      logInfo "User chose to generate a new SSH key"
      # Ask user for his email address
      if git_generate_keypair selected_file; then
        eval "$private_key='${selected_file}'"
        return 0
      else
        return 1
      fi
      ;;
    3)
      logInfo "User chose to paste an existing SSH private key"
      # Ask user for key, read input and write to file
      if git_paste_key selected_file; then
        eval "$private_key='${selected_file}'"
        return 0
      else
        return 1
      fi
      ;;
    *)
      local ssh_file="${ssh_files[$((choice - 4))]}"
      logInfo "User chose to use existing private key: ${ssh_file}"
      selected_file="${ssh_file}"
      eval "$private_key='${selected_file}'"
      return 0
      ;;
  esac

  return 1
}

# Guide the user in generating a new keypair
#
# Parameters:
#   $1[out]: Absolute path to the private key
# Returns:
#   0: If a key was selected (See $1)
#   1: If an error occured, and we must proceed without a key
git_generate_keypair() {
  local _prv_key="$1"
  local file
  local email
  local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"

  # Ask for email address
  read -rp "Enter your email address: " email
  if [[ -z "${email}" ]]; then
    echo "Error: Email address cannot be empty" >&2
    return 1
  fi

  # Check with regex it's a valid email
  if [[ $email =~ $regex ]]; then
    if ! git_next_key_name file "${ssh_dir}" "git_id_ed25519"; then
      logError "Unable to select a file for next key"
      return 1
    fi
    logInfo "Generating SSH key: ${file}"

    if ! ssh-keygen -t ed25519 -C "${email}" -f "${file}"; then
      logError "Failed to generate SSH key"
      return 1
    else
      eval "$_prv_key='${file}'"
      cat <<EOF
******************************************************
Your new private key was generated in: ${file}
You will now need to configure your public key so your identify will be accepted by the git server.
For github, follow the instructions here: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account?tool=webui

Below is what you will need to paste:
---------------------------------
$(cat "${file}.pub")
---------------------------------
Press [Enter] when you are done registering your key
EOF
    # Wait for user to press Enter
    read
    fi
  else
    echo "Error: This is not a valid email address" >&2
    return 1  # Invalid email
  fi

  return 0
}

# Ask user to paste his private key
#
# Parameters:
#   $1[out]: Absolute path to the private key
# Returns:
#   0: If a key was selected (See $1)
#   1: If an error occured, and we must proceed without a key
git_paste_key() {
  local _prv_key="$1"
  local file

  if ! git_next_key_name file "${ssh_dir}" "git_key"; then
    logError "Unable to select a file for next key"
    return 1
  fi

  cat <<EOF
======================================
====== SSH Private key required ======
======================================
1. Please paste the private key
2. press [Enter]
3. Press Ctrl+D to finish.
______________________________________
EOF

  # Read in the private key
  cat > "${file}"
  eval "$_prv_key='${file}'"
  cat <<EOF
______________________________________
EOF
  chmod 600 "${file}"
  return 0
}

# Returns the next key filename to use
#
# Parameters:
#   $1[out]: Filename for the key
#   $2[in]:  Directory where this key will be stored
#   $3[in]:  Prefix fpr the filename
# Returns:
#   0: If a filename was generated
#   1: If an error occured
git_next_key_name() {
  local _filename="$1"
  local dir_key="$2"
  local prefix="$3"

  if [[ ! -d "${dir_key}" ]]; then
    logError "The key direcotry does not exists: ${dir_key}"
    return 1  
  fi
  
  # Find an available filename
  local myfile
  local i=0
  while [[ -f "${dir_key}/${3}_${i}" ]]; do
    ((i++))
  done
  myfile="${dir_key}/${3}_${i}"
  logInfo "Filename generation: ${myfile}"
  touch "${myfile}"
  eval "$_filename='${myfile}'"
  rm -f "${myfile}"
  return 0
}

###########################
###### Startup logic ######
###########################

DQ_ARGS=("$@")
DQ_CWD=$(pwd)
DQ_ME="$(basename "$0")"

# Get directory of this script
# https://stackoverflow.com/a/246128
DQ_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${DQ_SOURCE}" ]]; do # resolve $DQ_SOURCE until the file is no longer a symlink
  DQ_ROOT=$(cd -P "$(dirname "${DQ_SOURCE}")" >/dev/null 2>&1 && pwd)
  DQ_SOURCE=$(readlink "${DQ_SOURCE}")
  [[ ${DQ_SOURCE} != /* ]] && DQ_SOURCE=${DQ_ROOT}/${DQ_SOURCE} # if $DQ_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DQ_ROOT=$(cd -P "$(dirname "${DQ_SOURCE}")" >/dev/null 2>&1 && pwd)
DQ_ROOT=$(realpath "${DQ_ROOT}/..")

# Import dependencies
source ${DQ_ROOT}/src/slf4sh.sh
source ${DQ_ROOT}/src/pkg.sh

if [[ -p /dev/stdin ]]; then
  # This script was piped
  echo "ERROR: This script cannot be piped"
  exit 1
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  # echo "ERROR: This script cannot be executed"
  # exit 1
  git_ssh_config
fi