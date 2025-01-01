#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# This interactive script is the entry point for setting up an environemnt
# using git as a source. As such, this script is intended to exist
# standalone without any dependencies. It is designed to be used
# as a helper in one-liner setup calls like those piped directly from wget.
#
# Conceptually, this script is idempotent, can be called multiple times and will only
# apply the changes not applied during prior executions. Aslo, this script strives in making sure
# no permanent changes to the system are made, outside of checking out the specified repository.
#
# Example usage:
# wget -qO- 'https://raw.githubusercontent.com/jeremfg/setup/refs/heads/main/src/git_setup.sh' | bash -s git@github.com:jeremfg/setup.git main -- echo "Done"
#
# From this example, you can see that the goal is to start from a freshly installed Linux OS,
# completely vanilla, and by pasting a single command in the terminal, the following will be pefromed:
#   1. Download this script from the Internet
#   2. Execute it, and while passing the right arguments, will do the following where/when needed
#   3. Install git, configure SSH, clone git repository.
#   4. Execute a custom command, relative to the root of the cloned repository.
#
# It is assumed that after step 4 above, more specific setup will be performed by scripts provided.
# This script is only the entry point to get the ball rolling, but the setup repo as a whole is designed
# to be used like a library, sharing code to create more complex stage-2 setup scripts
#
# Currently tested on the following OSes:
# - XCP-ng 8.3 (CentOS)
# - Ubuntu 24.04
#
# Known to work with the following versions of git:
# - 1.8.3.1
# - 2.43.0

SG_VERSION="0.1.0"
SG_NAME="setup_git"

# Entry point
setup_git() {
  # Keep a copy of entry arguments
  declare -g SG_ARGS=("$@")

  # Parse arguments
  # shellcheck disable=SC2119
  if ! sg_parse_args; then
    sg_print "Failed to parse arguments"
    return 1
  fi

  # Do we need to checkout a git repository?
  if [[ -z "${SG_REPO_URL}" ]]; then
    sg_print "No repository to checkout. Done."
    return 0
  fi

  if ! sg_pkg_install "git"; then
    sg_print "Failed to install git"
    return 1
  fi

  local dir
  if ! sg_clone_repository dir; then
    sg_print "Failed to clone repository"
    return 1
  fi

  # Cleanup after all operations performed by this script
  sg_cleanup

  # Execute entry point
  if [[ -n "${SG_COMMAND}" ]]; then
    local res

    pushd "${dir}" >/dev/null || return 1
    cat <<EOF
======================================
${SG_NAME} completed execution successfully.
Now executing the requested command:
${SG_COMMAND[*]}
======================================
EOF
    # shellcheck disable=SC2068
    ${SG_COMMAND[@]}
    res=$?
    popd >/dev/null || return 1

    # shellcheck disable=SC2248
    return ${res}
  fi

  return 0
}

# Get the repository in order
#
# Parameters:
#   $1[out]: Location of repository
sg_clone_repository() {
  local ret_dir="$1"

  # Determine repo status and clone location
  local _dir
  local _res
  sg_git_prepare_clone _dir "${SG_REPO_URL}"
  _res=$?
  eval "${ret_dir}='${_dir}'"
  case ${_res} in
  0)
    return 0
    ;;
  2)
    # Proceed with cloning
    ;;
  1)
    return 1
    ;;
  *)
    sg_print "Unexpected return from clone preparation: ${_res}"
    return 1
    ;;
  esac

  # Check if http URL, or assume SSH
  if [[ "${SG_REPO_URL}" =~ ^http.* ]]; then
    : # Nothing to dp
  else
    # Assume SSH
    if ! sg_ssh_prepare; then
      echo "Cannot use SSH"
      return 1
    fi
    while true; do
      sg_ssh_test_connection "${SG_REPO_URL}"
      _res=$?
      case ${_res} in
      0)
        # SSH access is working
        break
        ;;
      1)
        # Permissions denied? Try another key
        local new_key
        new_key=$(mktemp)
        SG_KEYS_TO_CLEANUP+=("${new_key}")
        if ! sg_ssh_paste_key "${new_key}"; then
          sg_print "No key obtained"
          return 1
        fi
        if ! ssh-add "${new_key}"; then
          sg_print "ssh-add returned an error"
          return 1
        fi
        ;;
      2)
        sg_print "Unrecoverable error occured when trying to connect via SSH"
        return 1
        ;;
      *)
        sg_print "Unexpected return from SSH test: ${_res}"
        return 1
        ;;
      esac
    done
  fi

  if ! git clone --recursive -b "${SG_GIT_REF}" "${SG_REPO_URL}" "${_dir}"; then
    sg_print "Failed to clone repository"
    rm -rf "${_dir}"
    return 1
  fi

  return 0
}

# Prepare for SSH operations
#
# Returns:
#   0: SSH operations ready
#   1: SSH is not going to work
sg_ssh_prepare() {
  # Make sure ssh, ssh-agent, ssh-keygen and ssh-add are available
  if ! command -v ssh &>/dev/null; then
    sg_print "ssh not found"
    return 1
  fi
  if ! command -v ssh-agent &>/dev/null; then
    sg_print "ssh-agent not found"
    return 1
  fi
  if ! command -v ssh-keygen &>/dev/null; then
    sg_print "ssh-add not found"
    return 1
  fi
  if ! command -v ssh-add &>/dev/null; then
    sg_print "ssh-add not found"
    return 1
  fi

  # Make sure SSH agent is running. Start it otherwise
  if [[ -z "${SSH_AUTH_SOCK}" ]]; then
    sg_trap_exit_add sg_cleanup
    sg_print "Starting SSH agent"
    eval "$(ssh-agent -s || true)"
    SG_AGENT_STARTED="true"
  else
    sg_print "SSH agent already running"
  fi
}

# Trap to cleanup ssh credentials
sg_cleanup() {
  # Cleanup SSH credentials
  local cur_key
  for cur_key in "${SG_KEYS_TO_CLEANUP[@]}"; do
    sg_print "Removing SSH key: ${cur_key}"
    ssh-add -d "${cur_key}"
    rm -f "${cur_key}"
  done
  SG_KEYS_TO_CLEANUP=()

  # Cleanup SSH agent
  if [[ -n "${SG_AGENT_STARTED}" ]]; then
    sg_print "Stop SSH agent"
    ssh-agent -k
    SG_AGENT_STARTED=""
  fi

  sg_print "Cleanup complete"
}

# shellcheck disable=SC2120
sg_parse_args() {
  local short="hv"
  local long="help,version"

  if ! command -v getopt &>/dev/null; then
    sg_print "getopt not found"
    return 1
  fi

  # First pass to scan for "--"
  declare -g SG_COMMAND=()
  local real_args=()
  local is_command=false

  for arg in "${SG_ARGS[@]}"; do
    if [[ "${is_command}" == "true" ]]; then
      SG_COMMAND+=("${arg}")
    elif [[ "${arg}" == "--" ]]; then
      is_command=true
    else
      real_args+=("${arg}")
    fi
  done

  # Second pass to parse the actual command line arguments
  local parsed
  if ! parsed=$(getopt --options "${short}" --long "${long}" --name "${SG_NAME}" -- "${real_args[@]}"); then
    sg_print "Failed to parse arguments"
    sg_print_usage
    return 1
  fi

  eval set -- "${parsed}"
  while true; do
    case "$1" in
    -h | --help)
      sg_print_usage
      return 0
      ;;
    -v | --version)
      echo "${SG_VERSION}"
      return 0
      ;;
    --)
      shift # Remaining arguments are positional
      break
      ;;
    *)
      sg_print "Invalid option: $1"
      shift
      sg_print_usage
      return 1
      ;;
    esac
  done

  # Handle positional arguments
  while [[ $# -gt 0 ]]; do
    if [[ -z "${SG_REPO_URL}" ]]; then
      declare -g SG_REPO_URL="${1}"
      shift
    elif [[ -z "${SG_GIT_REF}" ]]; then
      declare -g SG_GIT_REF="${1}"
      shift
    else
      sg_print "Too many arguments"
      sg_print_usage
      return 1
    fi
  done

  # Validate mandatory arguments
  if [[ -z "${SG_REPO_URL}" ]]; then
    sg_print "Missing repository URL"
    sg_print_usage
    return 1
  fi

  return 0
}

# Print a message to the console.
#
# Parameters:
#   $1[in]: Message to print
sg_print() {
  # Try to use logInfo, if available
  if typeset -f logInfo >/dev/null; then
    logInfo "${1}"
  else
    if [[ -n "${1}" ]]; then
      echo "${1}"
    else
      # Message was piped
      cat
    fi
  fi
}

sg_print_usage() {
  cat <<EOF
This script setup a git repository on a fresh environment

Usage: ${SG_NAME} [OPTIONS] <repo_url> [<git_ref>] [-- <command>]

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

# Global variables
SG_KEYS_TO_CLEANUP=()
SG_AGENT_STARTED=""

######################################################
######################################################
#################### LIBRARY CODE ####################
######################################################
######################################################

# The code below shouldn't be here, but is needed to keep this file
# independent and standalone. True libraries import this setup
# file to keep good code re-use practices.

# Global variables
SG_ENV_FILE_BACKUP="/tmp/backup.env"
SG_PK_UPDATED=0
SG_TRAPS=()

# Backup the current environment variables
sg_var_backup() {
  declare -p >"${SG_ENV_FILE_BACKUP}"
  sg_print "Environment variables have been backed up to: ${SG_ENV_FILE_BACKUP}"
  return 0
}

# Restore previously backed up environment variables
#
# Returns:
#   0: If variables were restored succesfully
#   1: If backup was not found
sg_var_restore() {
  if [[ ! -f "${SG_ENV_FILE_BACKUP}" ]]; then
    sg_print "Backup file does not exist: ${SG_ENV_FILE_BACKUP}"
    return 1
  fi

  # Source the backup file to restore the shell variables
  # shellcheck disable=SC1090
  source "${SG_ENV_FILE_BACKUP}" 2 &>/dev/null # Hide complaints about readonly variables
  sg_print "Shell variables have been restored from: ${SG_ENV_FILE_BACKUP}"

  return 0
}

# Identify the current OS
#
# Parameters:
#   $1[out]: Current OS
sg_os_identify() {
  local _os="$1"
  local file_os_release="/etc/os-release"
  sg_print "Performing OS identification..."

  if [[ -f "${file_os_release}" ]]; then
    sg_print "Sourcing: ${file_os_release}"
    sg_var_backup # Some of our variables might get overwritten. We'll restore later
    # shellcheck disable=SC1090
    source "${file_os_release}"
    # Print name and version
    if [[ -n "${NAME}" && -n "${VERSION}" ]]; then
      sg_print "Trying to identify ${NAME} Version ${VERSION}"
    fi

    # Iterate over all values in ID and ID_LIKE, in order
    local curId
    for curId in ${ID} ${ID_LIKE}; do
      case ${curId} in
      centos)
        eval "${_os}='centos'"
        sg_print "Identified centos"
        break
        ;;
      ubuntu)
        eval "${_os}='ubuntu'"
        sg_print "Identified ubuntu"
        break
        ;;
      *)
        sg_print "Unknown OS: ${curId}"
        ;;
      esac
    done
    sg_var_restore
    if [[ -z "${_os}" ]]; then
      return 1
    else
      return 0
    fi
  else
    sg_print "No OS information found. File '${file_os_release}' does not exist."
    sg_print <<EOF
======================================
=== Start of available information ===
======================================
=== uname -a ===
$(uname -a || true)

=== lsb_release -a ===
$(lsb_release -a || true)

=== /etc/*release files ===
EOF
    local releaseFile
    for releaseFile in /etc/*release; do
      if [[ -f ${releaseFile} ]]; then
        sg_print "=== Contents of ${releaseFile} ==="
        sg_print <"${releaseFile}"
      fi
    done
    sg_print <<EOF
======================================
==== End of available information ====
======================================
EOF
  fi

  return 1
}

# Install the package specified (if not already installed)
#
# Parameters:
#   $@: List of packages
# Returns:
#   0: Packages are installed
#   1: Failure
sg_pkg_install() {
  sg_pkg_install_from "" "$@"
}

# Install the package specified (if not already installed)
#
# Parameters:
#   $1: Repo to enable/install from
#   $@: List of packages
# Returns:
#   0: Packages are installed
#   1: Failure
sg_pkg_install_from() {
  local repo="$1"
  shift
  sg_print "Asked to install the following packages [${repo}]: $*"

  # First, check which OS we are running
  local cur_os
  if ! sg_os_identify cur_os; then
    sg_print "Could not identify OS"
    return 1
  fi

  # Functions we will need
  local fct_update
  local fct_is_installed
  local fct_install
  fct_update="sg_pkg_update_${cur_os}"
  fct_is_installed="sg_pkg_is_installed_${cur_os}"
  fct_install="sg_pkg_install_${cur_os}"

  # Update catalog
  if [[ ${SG_PK_UPDATED} -eq 0 ]]; then
    if ! eval "${fct_update}" "\"${repo}\""; then
      sg_print "Failed to update catalog"
      return 1
    else
      sg_print "Catalog updated successfully"
      SG_PK_UPDATED=1
    fi
  else
    sg_print "Catalog is already up to date"
  fi

  local to_install=()
  local cur_pkg
  local res
  # Check which packages need to be installed
  for cur_pkg in "$@"; do
    sg_print "Checking if package \"${cur_pkg}\" is alread installed"
    eval "${fct_is_installed}" "\"${repo}\"" "\"${cur_pkg}\""
    res=$?
    if [[ ${res} -eq 1 ]]; then
      sg_print "Failed to check if package \"${cur_pkg}\" is installed"
      return 1
    elif [[ ${res} -eq 2 ]]; then
      sg_print "Package \"${cur_pkg}\" is not installed"
      to_install+=("${cur_pkg}")
    else
      sg_print "Package \"${cur_pkg}\" is already installed"
    fi
  done

  # Check if we have something to install
  if [[ ${#to_install[@]} -gt 0 ]]; then
    if ! eval "${fct_install}" "\"${repo}\"" "\"${to_install[*]}\""; then
      sg_print "Failed to install packages"
      return 1
    fi
  else
    sg_print "Nothing to install"
  fi

  return 0
}

sg_pkg_update_centos() {
  sg_print "Nothing to update with yum"
  return 0
}

# Checks if a package is installed using yum
#
# Parameters:
#   $1: Repo to enable
#   $2: package to check
# Returns:
#   0: Package is installed
#   1: Package is not installed
#   2: Error
sg_pkg_is_installed_centos() {
  local repo="$1"
  local cur_pkg="$2"
  local res=2

  local repo_en=""
  if [[ -n "${repo}" ]]; then
    repo_en="--enablerepo=${repo}"
  fi

  if yum list installed "${cur_pkg}" &>/dev/null; then
    res=0
  else
    if yum "${repo_en}" list available "${cur_pkg}" &>/dev/null; then
      res=1
    else
      res=2
    fi
  fi

  # shellcheck disable=SC2248
  return ${res}
}

# Install packages using yum
#
# Parameters:
#   $1: Repo to enable
#   $@: List of packages to install
sg_pkg_install_centos() {
  local repo="$1"
  shift
  local pkgs=("$@")

  local repo_en=""
  if [[ -n "${repo}" ]]; then
    repo_en="--enablerepo=${repo}"
  fi

  sg_print "Installing from ${repo} packages: ${pkgs[*]}"

  if yum "${repo_en}" install -y "${pkgs[@]}"; then
    return 0
  else
    return 1
  fi
}

# Ask user to paste his private key
#
# Parameters:
#   $1[in]: Absolute file path where the key shall be stored
# Returns:
#   0: If a key was selected (See $1)
#   1: If an error occured, and we must proceed without a key
sg_ssh_paste_key() {
  local _prv_key="$1"

  if [[ -z "${_prv_key}" ]]; then
    sg_print "No file provided"
    return 1
  fi

  cat <<EOF
======================================
====== SSH Private key required ======
======================================
1. Please paste the private key below.
2. Press [Enter] to end on a new l ine.
3. Press Ctrl+D to finish.
______________________________________
EOF

  # Read in the private key from /dev/tty
  local _prv_key_content
  _prv_key_content=$(cat /dev/tty)
  echo "${_prv_key_content}" >"${_prv_key}"
  cat <<EOF
______________________________________
EOF
  chmod 600 "${_prv_key}"
  return 0
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
sg_git_find_root() {
  local _root="${1}"
  local _start_dir="${2}"
  local _cur_dir

  # Cleanup start directory
  _start_dir=$(realpath "${_start_dir}")
  if [[ -z "${_start_dir}" ]]; then
    sg_print "Initial directory invalid"
    return 1
  fi

  # First, search up the hierarchy until we find a valid directory
  _cur_dir="${_start_dir}"
  while [[ ! -d "${_cur_dir}" ]]; do
    if [[ -z "${_cur_dir}" ]] || [[ "/" == "${_cur_dir}" ]]; then
      # We've reached the top without finding a directory. Assuming error
      sg_print "Stopped search after reaching root"
      return 1
    fi
    # Go one level up
    _cur_dir="$(realpath "${_start_dir}/..")"
  done

  # Ok, from this point we have a valid directory. Now we need to check for git
  if cd "${_cur_dir}" && git rev-parse --is-inside-work-tree &>/dev/null; then
    local _next_dir="${_cur_dir}"
    while true; do
      _next_dir="$(cd "${_cur_dir}" && git rev-parse --show-toplevel)/.."
      _next_dir="$(realpath "${_next_dir}")"
      if cd "${_next_dir}" && git rev-parse --is-inside-work-tree &>/dev/null; then
        _cur_dir="${_next_dir}"
      else
        _cur_dir="$(cd "${_cur_dir}" && git rev-parse --show-toplevel)"
        eval "${_root}='${_cur_dir}'"
        return 0
      fi
    done
  else
    # Not a git repository
    eval "${_root}='${_start_dir}'"
    return 2
  fi
}

# Prepare before a clone makes sure a clone is required
#
# Parameters:
#   $1[out]: Directory where cloning should be performed
#   $2[in]:  Repo URL
# Returns:
#   0: Cloning not required, but otherwise good
#   1: Cloning not required, because of an error
#   2: Cloning required and ready
sg_git_prepare_clone() {
  local _repo_dir="${1}"
  local _url="${2}"
  local _res=0

  # Get repo name from URL
  local repoName checkout_dir
  repoName=$(basename "${_url}")
  repoName=${repoName%.git} # Remove .git extension

  # Determine location where we should be checking out
  checkout_dir=$(pwd)
  sg_git_find_root checkout_dir "${checkout_dir}"
  _res=$?
  case ${_res} in
  0)
    checkout_dir="$(realpath "${checkout_dir}/../${repoName}")"
    sg_print "Git-relative checkout directory is: ${checkout_dir}"
    ;;
  1)
    sg_print "Failed to find a proper checkout location"
    return 1
    ;;
  2)
    checkout_dir="${checkout_dir}/${repoName}"
    sg_print "Checkout directory is: ${checkout_dir}"
    ;;
  *)
    sg_print "Unexpected return code for root location: ${_res}"
    return 1
    ;;
  esac

  eval "${_repo_dir}='${checkout_dir}'"

  # Prepare location
  if [[ ! -d "${checkout_dir}" ]]; then
    # Location is clean, we can create an empty repo
    sg_print "Create directory: ${checkout_dir}"
    if ! mkdir -p "${checkout_dir}"; then
      sg_print "Failed to create directory"
      return 1
    fi
    return 2 # Ready to clone
  elif cd "${checkout_dir}" && git rev-parse --is-inside-work-tree &>/dev/null; then
    # This is already a git repository. But perhaps it's the same one we want?
    if [[ "$(cd "${checkout_dir}" && git config --get remote.origin.url || true)" != "${_url}" ]]; then
      sg_print "Turns out there's a different repository at this location"
      return 1
    fi
    sg_print "Repository already cloned"
    return 0
  elif [[ -z "$(ls -A "${checkout_dir}" || true)" ]]; then
    sg_print "Directory is empty, this is a suitable location"
    return 2
  else
    sg_print "Directory is not empty"
    return 1
  fi
}

# Test connection to SSH server, making sure credentials are good
#
# Parameters:
#   $1[in]: Url to test
# Returns:
#   0: Connection successful
#   1: Bad credentials
#   2: Other error
sg_ssh_test_connection() {
  local _test_url="${1}"
  local res=0
  local res2

  res2=$(ssh -o StrictHostKeyChecking=no -T "${_test_url%:*}" 2>&1)
  res=$?
  if [[ ${res} -eq 255 ]]; then
    sg_print "SSH connexion denied: ${res2}"
    res=1
  elif [[ ${res} -eq 1 ]]; then
    # Inspect the error message
    if [[ "${res2}" == *"You've successfully authenticated"* ]]; then
      sg_print "Recognized the github.com welcome message"
      res=0
    else
      logError "Unrecognized SSH connection message on err 1: ${res2}."
      res=2
    fi
  elif [[ ${res} -eq 0 ]]; then
    sg_print "Connection successful: ${res2}"
    res=0
  else
    sg_print "Unkown SSH connection error: ${res} - ${res2}."
    res=2
  fi

  # shellcheck disable=SC2248
  return ${res}
}

# Add a trap function to be called on process exit
# This is typically used for cleanup functions
#
# Paramters:
#   $1[in]: Function to call
# Returns:
#   0: Function added or was already registered
sg_trap_exit_add() {
  local new_trap="${1}"
  local nb_traps

  # Current number of traps
  nb_traps="${#SG_TRAPS[@]}"

  local found
  for t in "${SG_TRAPS[@]}"; do
    if [[ "${t}" == "${new_trap}" ]]; then
      found=true
    fi
  done

  if [[ -z "${found}" ]]; then
    SG_TRAPS+=("${new_trap}")
    if [[ ${nb_traps} -eq 0 ]]; then
      # This was the first trap, register ourselves to the process
      trap sg_trap_exit EXIT
    fi
  fi

  return 0
}

# Actual trap called on Exit
sg_trap_exit() {
  # Loop and call every registered traps
  for t in "${SG_TRAPS[@]}"; do
    sg_print "Clenaup calling: ${t}"
    eval "${t}"
  done

  return 0
}

# Variables loaded externally
ID=""
ID_LIKE=""

###########################
###### Startup logic ######
###########################

if [[ -p /dev/stdin ]] && [[ -z ${BASH_SOURCE[0]} ]]; then
  # This script was piped
  setup_git "${@}"
  exit $?
elif [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  # This script was sourced
  :
else
  # This script was executed
  setup_git "${@}"
  exit $?
fi
