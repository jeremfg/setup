# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# This script is used to configure git

if [[ -z ${GUARD_GIT_SH} ]]; then
  GUARD_GIT_SH=1
else
  return 0
fi

git_install() {
  logTrace "Configuring git"

  if command -v git &>/dev/null; then
    logInfo "Git is already installed"
    return 0
  fi

  logInfo "Installing git..."
  if ! pkg_install "git"; then
    logError "Could not install git"
    return 1
  else
    if command -v git &>/dev/null; then
      return 0
    else
      logError "Could not detect git installation"
      return 1
    fi
  fi
}

# Interactive configuration for git
#
# Parameters:
#   $1[in]: Directory for the repository
git_configure() {
  local repo_dir="$1"

  logTrace "Configuring git"
  if [[ -z "${repo_dir}" ]]; then
    if ! git_find_root repo_dir "${GG_ROOT}"; then
      logError "Failed to find the root of the repository"
      return 1
    else
      logWarn "No repository directory provided. Assuming: ${repo_dir}"
    fi
  fi

  # shellcheck disable=SC2119
  if ! git_ssh_config; then
    logError "Failed to configure SSH access for git"
    return 1
  fi

  if ! pushd "${repo_dir}" >/dev/null; then
    logError "Failed to change directory to ${repo_dir}"
    return 1
  fi

  # Make sure user is configured
  local cur_user
  local cur_email
  cur_user=$(cd "${repo_dir}" && git config user.name)
  cur_email=$(cd "${repo_dir}" && git config user.email)

  # If git user is not configured, ask the user about it
  local user
  local email
  if [[ -z "${cur_user}" ]] || [[ -z "${cur_email}" ]]; then
    # Ask user if he's happy withy the current user, providing the current as default
    cat <<EOF
*******************************
****** Git Configuration ******
*******************************
The following user is currently configured

  ${cur_user} <${cur_email}>

Please change the values if needed (10 seconds timeout)
EOF
    os_ask_user user "Git friendly user" "${cur_user}"
    os_ask_user email "Git email address" "${cur_email}"

    if [[ "${cur_user}" != "${user}" ]] || [[ "${cur_email}" != "${email}" ]]; then
      logInfo "Setting git user to: ${user} <${email}>"
    fi
    if [[ "${cur_user}" != "${user}" ]]; then
      if ! git config user.name "${user}"; then
        logError "Failed to set git user"
        popd >/dev/null || return 1
        return 1
      fi
    fi
    if [[ "${cur_email}" != "${email}" ]]; then
      if ! git config user.email "${email}"; then
        logError "Failed to set git email"
        popd >/dev/null || return 1
        return 1
      fi
    fi
  else
    user="${cur_user}"
    email="${cur_email}"
  fi

  # Configure push.default to simple, if not already set
  local push_default
  push_default=$(git config push.default)
  if [[ "${push_default}" != "simple" ]]; then
    logInfo "Setting push.default to simple"
    if ! git config push.default simple; then
      logError "Failed to set push.default"
      popd >/dev/null || return 1
      return 1
    fi
  fi

  # Apply configurations to all submodules
  # shellcheck disable=SC2016
  if ! user="${user}" email="${email}" git submodule foreach '
    cur_user=$(git config user.name)
    cur_email=$(git config user.email)

    if [[ "${cur_user}" != "${user}" ]] || [[ "${cur_email}" != "${email}" ]]; then
      echo "Setting git user to: ${user} <${email}> in submodule ${name}"
    fi
    if [[ "${cur_user}" != "${user}" ]]; then
      if ! git config user.name "${user}"; then
        echo "Failed to set git user in submodule ${name}"
        exit 1
      fi
    fi
    if [[ "${cur_email}" != "${email}" ]]; then
      if ! git config user.email "${email}"; then
        echo "Failed to set git email in submodule ${name}"
        exit 1
      fi
    fi

    push_default=$(git config push.default)
    if [[ "${push_default}" != "simple" ]]; then
      echo "Setting push.default to simple in submodule ${name}"
      if ! git config push.default simple; then
        echo "Failed to set push.default in submodule ${name}"
        exit 1
      fi
    fi
  '; then
    logError "Failed to apply git configuration to submodules"
    popd >/dev/null || return 1
    return 1
  fi

  popd >/dev/null || return 1
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
git_find_root() {
  sg_git_find_root "${1}" "${2}"
  return $?
}

# Configure git for SSH access. This is an interactive function
#
# Parameters:
#   $1[in] URL to the git server. If none provided, Github is assuenmd
# Returns:
#   0: If SSH access was succesfully configured
#   1: If SSH configuration failed
# shellcheck disable=SC2120
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

  if [[ ${res} -ne 0 ]]; then
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
  for key in "${keys_to_clean[@]}"; do
    if [[ ${res} -ne 0 ]] || [[ "${key}" == "${actual_key}" ]]; then
      if ! ssh-add -d "${key}"; then
        logWarn "Could not unregister key: ${key}"
      fi
      if ! rm -f "${key}"; then
        logWarn "Failure to delete private key ${key}"
      fi
      if ! rm -f "${key}.pub"; then
        logWarn "Failure to delete private key ${key}.pub"
      fi
    fi
  done
  keys_to_clean=()

  # shellcheck disable=SC2248
  return ${res}
}

###########################
###### Startup logic ######
###########################

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
if ! source "${GG_ROOT}/src/pkg.sh"; then
  logFatal "Failed to import pkg.sh"
fi
if ! source "${GG_ROOT}/src/ssh.sh"; then
  logFatal "Failed to import ssh.sh"
fi
if ! source "${GG_ROOT}/src/setup_git"; then
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
