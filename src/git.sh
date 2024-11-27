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

# Search for the parent/root of the top repository,
# walking up submodules if present
#
# Parameters:
#   $1[out]: Top root found
#   $2[in]:  Start directory to search from
# Returns:
#   0: Top root found
#   1: Error, not even a valid location
#   2: Not a git directory. $1=$2
git_find_root() {
  sg_git_find_root $1 $2
  return $?
}

# Configure git for SSH access. This is an interactive function
#
# Parameters:
#   $1[in] URL to the git server. If none provided, Github is assuenmd
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

  # Make sure the SSH agent is running
  if ! ssh_agent_install; then
    return 1
  fi

  # Loop until we get SSH access
  local res
  local key
  local actual_key=""
  local keys_to_clean=()
  while true; do
    ssh_test_connection "${git_server}"
    res=$?
    case ${res} in
      0)
        # SSH key is working
        break
        ;;
      1)
        # Permissions denied? Try another key
        ssh_next_key_name key "git_key"
        if ! ssh_ask actual_key "${key}"; then
          # Break the loop, to allow the cleanup to still run
          res=2
          actual_key=""
          break
        fi

        # This means this was a generated key, and we want to delete it if it doesn't work
        if [[ "${key}" == "${actual_key}" ]]; then  
          keys_to_clean+=("${actual_key}")
        fi

        # Configure this key, so it's usable for the upcoming test
        if ! ssh-add "${actual_key}"; then
          # Break the loop, to allow the cleanup to still run
          res=2
          actual_key=""
          break
        fi
        ;;
      2)
        logError "Unrecoverable error occured when trying to connect via SSH"
        break
        ;;
      *)
        logError "Unexpected return from SSH test: ${res}"
        break
        ;;
    esac
  done

  if [[ $res -ne 0 ]]; then
    # In case of error, de-register the last key we tried
    if [[ -n "${actual_key}" ]]; then
      if ! ssh-add -d "${actual_key}"; then
        logWarn "An error occured while trying to remove a useless key from the ssh agent"
      fi
    fi
  else
    # Install the new valid key
    if [[ -n "${actual_key}" ]]; then
      if ! ssh_key_install "${actual_key}"; then
        logError "Failed to install the working key: ${actual_key}"
        res=2
      fi
    fi
  fi

  # Cleanup keys
  for key in ${keys_to_clean}; do
    if ! ssh-add -d "${key}"; then
      logWarn "Could not unregister key: ${key}"
    fi
    if ! rm -f "${key}"; then
      logWarn "Failure to delete private key ${key}"
    fi
    if ! rm -f "${key}.pub"; then
      logWarn "Failure to delete private key ${key}.pub"
    fi
  done
  keys_to_clean=()

  return ${res}
}

###########################
###### Startup logic ######
###########################

GG_ARGS=("$@")
GG_CWD=$(pwd)
GG_ME="$(basename "$0")"

# Get directory of this script
# https://stackoverflow.com/a/246128
GG_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${GG_SOURCE}" ]]; do # resolve $GG_SOURCE until the file is no longer a symlink
  GG_ROOT=$(cd -P "$(dirname "${GG_SOURCE}")" >/dev/null 2>&1 && pwd)
  GG_SOURCE=$(readlink "${GG_SOURCE}")
  [[ ${GG_SOURCE} != /* ]] && GG_SOURCE=${GG_ROOT}/${GG_SOURCE} # if $GG_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
GG_ROOT=$(cd -P "$(dirname "${GG_SOURCE}")" >/dev/null 2>&1 && pwd)
GG_ROOT=$(realpath "${GG_ROOT}/..")

# Import dependencies
source ${GG_ROOT}/src/slf4sh.sh
source ${GG_ROOT}/src/pkg.sh
source ${GG_ROOT}/src/ssh.sh
source ${GG_ROOT}/src/setup_git.sh

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
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
  exit $?
fi