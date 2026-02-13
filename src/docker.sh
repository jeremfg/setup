# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# This script is used to install Docker Desktop on Linux

if [[ -z ${GUARD_DOCKER_SH} ]]; then
  GUARD_DOCKER_SH=1
else
  return 0
fi

# Install Docker Desktop (latest version with GUI)
#
# Returns:
#   0: Success
#   1: Failure

docker_install() {
  local config_file="$1"
  if [[ -z "${config_file}" ]]; then
    logError "Missing config file path for docker_install"
    return 1
  fi

  if command -v docker &>/dev/null; then
    logInfo "Docker is already installed"
    docker --version

    if ! pass_setup_gpg "${PASS_KEY_NAME}" "${config_file}"; then
      logError "Failed to configure pass for Docker Desktop"
      return 1
    fi

    return 0
  fi

  logInfo "Installing Docker Desktop..."

  # Detect OS
  local detected_os
  if ! os_identify detected_os; then
    logError "Failed to detect OS"
    return 1
  fi
  logInfo "Detected OS: ${detected_os}"

  # Add Docker's official GPG key
  logInfo "Adding Docker GPG key..."
  if ! sudo install -m 0755 -d /etc/apt/keyrings; then
    logError "Failed to create keyrings directory"
    return 1
  fi

  if ! sudo curl -fsSL "https://download.docker.com/linux/${detected_os}/gpg" -o /etc/apt/keyrings/docker.asc; then
    logError "Failed to download Docker GPG key"
    return 1
  fi

  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Remove any existing Docker repository configuration
  if [[ -f /etc/apt/sources.list.d/docker.list ]]; then
    logInfo "Removing old Docker repository configuration..."
    sudo rm -f /etc/apt/sources.list.d/docker.list
  fi

  # Add Docker repository
  logInfo "Adding Docker repository..."
  local arch
  arch=$(dpkg --print-architecture)

  # Get the appropriate codename for the repository
  # For Linux Mint and derivatives, use UBUNTU_CODENAME instead of VERSION_CODENAME
  local codename
  # shellcheck disable=SC1091
  if [[ "${detected_os}" == "ubuntu" ]]; then
    codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME}}")
  else
    codename=$(. /etc/os-release && echo "${VERSION_CODENAME}")
  fi

  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${detected_os} \
  ${codename} stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Update apt cache
  if ! sudo apt-get update; then
    logError "Failed to update apt cache"
    return 1
  fi

  # Download and install Docker Desktop (dependencies will be resolved automatically)
  logInfo "Installing Docker Desktop..."
  local temp_dir
  temp_dir=$(mktemp -d)
  local deb_file="${temp_dir}/docker-desktop.deb"

  if ! curl -fsSL "https://desktop.docker.com/linux/main/${arch}/docker-desktop-${arch}.deb" -o "${deb_file}"; then
    logError "Failed to download Docker Desktop"
    rm -rf "${temp_dir}"
    return 1
  fi

  if ! sudo apt-get install -y "${deb_file}"; then
    logError "Failed to install Docker Desktop"
    rm -rf "${temp_dir}"
    return 1
  fi

  rm -rf "${temp_dir}"

  # Verify installation
  if ! command -v docker &>/dev/null; then
    logError "Docker installation verification failed"
    return 1
  fi

  if ! pass_setup_gpg "${PASS_KEY_NAME}" "${config_file}"; then
    logError "Failed to configure pass for Docker Desktop"
    return 1
  fi

  logInfo "Docker Desktop installed successfully"
  docker --version

  return 0
}

PASS_KEY_NAME="DOCKER_PASS_KEYID"

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
DK_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${DK_SOURCE}" ]]; do # resolve $DK_SOURCE until the file is no longer a symlink
  DK_ROOT=$(cd -P "$(dirname "${DK_SOURCE}")" >/dev/null 2>&1 && pwd)
  DK_SOURCE=$(readlink "${DK_SOURCE}")
  [[ ${DK_SOURCE} != /* ]] && DK_SOURCE=${DK_ROOT}/${DK_SOURCE} # if $DK_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DK_ROOT=$(cd -P "$(dirname "${DK_SOURCE}")" >/dev/null 2>&1 && pwd)
DK_ROOT=$(realpath "${DK_ROOT}/..")

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
elif ! source "${DK_ROOT}/src/os.sh"; then
  echo "Failed to import os.sh"
  exit 1
elif ! source "${DK_ROOT}/src/pass.sh"; then
  echo "Failed to import pass.sh"
  exit 1
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
