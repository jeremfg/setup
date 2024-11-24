#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This interactive script is the entry point for setting up an environemnt
# using git as a source. As such, this script is intended to exist
# standalone without any dependencies. It is designed to be used
# as a helper in one-liner setup calls like piped directly from wget.
#
# Example usage:
# wget -qO- 'https://raw.githubusercontent.com/jeremfg/setup/refs/heads/main/src/git_setup.sh' | bash -s git@github.com:jeremfg/setup.git main -- echo "Done"
#
# Currently tested on the following OSes:
# - XCP-ng 8.3 (CentOS)
# - Ubuntu 24.04
# 
# Known to work with the following versions of git:
# - 1.8.3.1
# - 2.43.0

GS_VERSION="0.1.0"
GS_NAME="setup_git"

# Entry point
setup_git() {
  # Keep a copy of entry arguments
  declare -g GS_ARGS=("$@")

  # Parse arguments
  if ! gs_parse_args; then
    echo "Failed to parse arguments" >&2
    return 1
  fi

  # Do we need to checkout a git repository?
  if [[ -z "${GS_REPO_URL}" ]]; then
    return 0
  fi

  if ! gs_identify_os; then
    echo "OS identification failed" >&2
    return 1
  fi

  if ! gs_install_git; then
    echo "Failed to install git" >&2
    return 1
  fi

  if ! gs_clone_repository; then
    echo "Failed to clone repository" >&2
    return 1
  fi

  # Cleanup after all operations performed by this script
  gs_cleanup

  # Execute entry point
  if [[ -n "${GS_COMMAND}" ]]; then
    local res

    pushd "${GS_REPO_DIR}" > /dev/null
          cat <<EOF
======================================
${GS_NAME} completed execution successfully.
Now executing the requested command:
$(pwd)$ ${GS_COMMAND[@]}
======================================
EOF
    ${GS_COMMAND[@]}
    res=$?
    popd > /dev/null
    
    return $res
  fi

  return 0
}

gs_clone_repository() {  
  # Get repo name from URL
  local repoName
  repoName=$(basename ${GS_REPO_URL})
  repoName=${repoName%.git} # Remove .git extension

  local gitRoot
  gitRoot=$(pwd) # Initialize with current directory

  # Walk-up the tree to exit any potential git repository
  while true; do
    # Check if we are inside a git repository
    if cd "${gitRoot}" && git rev-parse --is-inside-work-tree &> /dev/null; then
      gitRoot="$(cd "${gitRoot}" && git rev-parse --show-toplevel)/.."
      gitRoot="$(realpath ${gitRoot})"
    else
      break; # We've escaped outside of the git repo
    fi
  done

  local repoDir="${gitRoot}/${repoName}"
  if [[ -d "${repoDir}" ]]; then
    # Check if this is a git repository
    if ! cd "${repoDir}" && git rev-parse --is-inside-work-tree &> /dev/null; then
      echo "Detected an invalid repository: ${repoDir}" >&2
      return 1
    fi
    # Make sure this is the same repository
    if [[ "$(cd "${repoDir}" && git config --get remote.origin.url)" != "${GS_REPO_URL}" ]]; then
      echo "Detected a different repository: ${repoDir}" >&2
      return 1
    fi
    # Fetch the latest changes
    gs_ssh_credentials
    cd "${repoDir}" && git fetch --all
  else
    # Clone the repository
    gs_ssh_credentials
    git clone --recursive -b "${GS_GIT_REF}" "${GS_REPO_URL}" "${repoDir}"
    if [[ $? -ne 0 ]]; then
      echo "Failed to clone repository" >&2
      rm -rf "${repoDir}"
      return 1
    fi
  fi

  declare -g GS_REPO_DIR="${repoDir}"
  return 0
}

# Trap to cleanup ssh credentials
gs_cleanup() {

  # Call previous trap
  if [[ -n "${gs_previous_trap}" ]]; then
    eval "${gs_previous_trap}"
    gs_previous_trap=""
  fi

  # Cleanup SSH credentials
  if [[ -n "${gs_private_key_file}" ]]; then
    ssh-add -d "$gs_private_key_file"
    rm -f "${gs_private_key_file}"
    gs_private_key_file=""
  fi

  # Cleanup SSH agent
  if [[ -n "${gs_ssh_agent_started}" ]]; then
    ssh-agent -k
    gs_ssh_agent_started=""
  fi
}

gs_ssh_credentials() {
  declare -g gs_private_key_file
  declare -g gs_ssh_agent_started
  declare -g gs_trap_previous
  declare -g gs_previous_trap
  local res

  # Check if the URL is an SSH URL
  if [[ "${GS_REPO_URL}" != "git@"* ]]; then
    echo "Not an SSH URL: ${GS_REPO_URL}"
    return 0
  fi

  # Make sure ssh, ssh-agent and ssh-add are available
  if ! command -v ssh &> /dev/null; then
    echo "ssh not found" >&2
    return 1
  fi
  if ! command -v ssh-agent &> /dev/null; then
    echo "ssh-agent not found" >&2
    return 1
  fi
  if ! command -v ssh-add &> /dev/null; then
    echo "ssh-add not found" >&2
    return 1
  fi

  # Setup exit trap
  gs_previous_trap=$(trap -p EXIT | sed -n -e 's/^trap -- \(.*\) EXIT$/\1/p')
  if [[ -n "${gs_previous_trap}" ]]; then
    echo "Previous trap found: ${gs_previous_trap}"
  fi
  trap gs_cleanup EXIT
  
  # Make sure SSH agent is running. Start it otherwise
  if [[ -z "${SSH_AUTH_SOCK}" ]]; then
    eval "$(ssh-agent -s)"
    gs_ssh_agent_started="true"
  else
    echo "SSH agent already running"
    gs_ssh_agent_started=""
  fi

  # Validate if we have SSH credentials
  gs_private_key_file=""
  while true; do
    # Test for connection
    res=$(ssh -o StrictHostKeyChecking=no -T "${GS_REPO_URL}")
    if [[ $? -eq 0 ]]; then
      echo "SSH credentials found"
      break
    else
      echo "No SSH credentials found"

      # Delete SSH key from previous loops
      if [[ -n "${gs_private_key_file}" ]]; then
        rm -f "${gs_private_key_file}"
      fi

      # New key
      gs_private_key_file=$(mktemp)

      # Ask user for key, read input and write to file
      cat <<EOF
======================================
====== SSH Private key required ======
======================================
A valid SSH private key is required to access the following repository:
${GS_REPO_URL}.

Please paste the private key below, press Enter, than press Ctrl+D to finish.
______________________________________
EOF
      cat > "${gs_private_key_file}"
      cat <<EOF
______________________________________
EOF
      chmod 600 "${gs_private_key_file}"

      ssh-add "$gs_private_key_file"

      break
    fi
  done
}

gs_identify_os() {
  declare -g GS_OS=""

  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    # Print name and version
    if [[ -n "${NAME}" && -n "${VERSION}" ]]; then
      echo "Trying to identify ${NAME} Version ${VERSION}"
    fi

    # Iterate over all values in ID and ID_LIKE, in order
    for curId in ${ID} ${ID_LIKE}; do
      case $curId in 
        centos)
          GS_OS="centos"
          break
          ;;
        ubuntu)
          GS_OS="ubuntu"
          break
          ;;
        *)
          echo "Unknown OS: ${curId}"
          ;;
      esac
    done
  else
    echo "No OS information found"
    echo "======================================"
    echo "=== Start of available information ==="
    echo "======================================"
    # Try to print some helpful information
    if command -v uname &> /dev/null; then
      uname -a
    fi
    if command -v lsb_release &> /dev/null; then
      lsb_release -a
    fi
    # For each realease file
    if command -v cat &> /dev/null; then
      for releaseFile in /etc/*release; do
        if [[ -f ${releaseFile} ]]; then
          echo "=== Contents of ${releaseFile} ==="
          cat ${releaseFile}
        fi
      done
    fi
    echo "======================================"
    echo "==== End of available information ===="
    echo "======================================"
  fi

  if [[ -n "${GS_OS}" ]]; then
    echo "OS identified as ${GS_OS}"
  else
    echo "OS identification failed" >&2
    return 1
  fi

  return 0
}

gs_install_git() {
  case ${GS_OS} in
    centos)
      if command -v git &> /dev/null; then
        echo "Git already installed"
      else
        echo "Installing git"
        sudo yum install -y git
        if [[ $? -ne 0 ]]; then
          echo "Failed to install git" >&2
          return 1
        fi
        if command -v git &> /dev/null; then
          echo "Git installed successfully"
        else
          echo "Git not found after installation" >&2
          return 1
        fi
      fi
      ;;
    ubuntu)
      if command -v git &> /dev/null; then
        echo "Git already installed"
      else
        echo "Installing git"
        sudo apt-get update -y
        sudo apt-get install -y git
        if [[ $? -ne 0 ]]; then
          echo "Failed to install git" >&2
          return 1
        fi
        if command -v git &> /dev/null; then
          echo "Git installed successfully"
        else
          echo "Git not found after installation" >&2
          return 1
        fi
      fi
      ;;
    *)
      echo "Unknown OS: ${GS_OS}" >&2
      return 1
      ;;
  esac

  return 0
}

gs_parse_args() {
  local short="hv"
  local long="help,version"

  if ! command -v getopt &> /dev/null; then
    echo "getopt not found" >&2
    return 1
  fi

  # First pass to scan for "--"
  declare -g GS_COMMAND=()
  local real_args=()
  local is_command=false

  for arg in "${GS_ARGS[@]}"; do
    if [[ "${is_command}" == "true" ]]; then
      GS_COMMAND+=("${arg}")
    elif [[ "${arg}" == "--" ]]; then
      is_command=true
    else
      real_args+=("${arg}")
    fi
  done

  # Second pass to parse the actual command line arguments
  local parsed
  if ! parsed=$(getopt --options ${short} --long ${long} --name "${GS_NAME}" -- "${real_args[@]}"); then
    echo "Failed to parse arguments" >&2
    gs_print_usage
    return 1
  fi

  eval set -- "${parsed}"
  while true; do
    case "$1" in
      -h|--help)
        gs_print_usage
        return 0
        ;;
      -v|--version)
        echo "${GS_VERSION}"
        return 0
        ;;
      --)
        shift # Remaining arguments are positional
        break
        ;;
      *)
        echo "Invalid option: $1" >&2
        shift
        gs_print_usage
        return 1
        ;;
    esac
  done

  # Handle positional arguments
  while [[ $# -gt 0 ]]; do
    if [[ -z "${GS_REPO_URL}" ]]; then
      declare -g GS_REPO_URL="${1}"
      shift
    elif [[ -z "${GS_GIT_REF}" ]]; then
      declare -g GS_GIT_REF="${1}"
      shift
    else
      echo "Too many arguments" >&2
      gs_print_usage
      return 1
    fi
  done

  # Validate mandatory arguments
  if [[ -z "${GS_REPO_URL}" ]]; then
    echo "Missing repository URL" >&2
    gs_print_usage
    return 1
  fi

  return 0
}

gs_print_usage() {
  cat <<EOF
This script setup a git repository on a fresh environment

Usage: ${GS_NAME} [OPTIONS] <repo_url> [<git_ref>] [-- <command>]

Arguments:
  repo_url     The URL of the git repository to clone
  command      The command to execute after cloning the repository. CWD will be the root of the repository.
  git_ref      The git reference to checkout (default: main)

Options:
  -h, --help     Print this help message
  -v, --version  Print the version of this script
EOF
  return 0
}

###########################
###### Startup logic ######
###########################

if [[ -p /dev/stdin ]]; then
  # This script was piped
  setup_git "${@}"
  exit $?
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  export -f setup_git
else
  # This script was executed
  setup_git "${@}"
  exit $?
fi
