# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Shared library for Android phone connections via ADB and scrcpy

if [[ -z ${GUARD_ANDROID_SH} ]]; then
  GUARD_ANDROID_SH=1
else
  return 0
fi

# Install Android development tools (scrcpy with ADB dependency)
#
# Returns:
#   0: Success
#   1: Failure
android_install() {

  if command -v scrcpy &>/dev/null; then
    logInfo "scrcpy is already installed, skipping Android tools installation"
    return 0
  fi

  logInfo "Installing Android development tools..."

  # Install scrcpy from the latest official release (not via apt)
  if [[ -z "${DOWNLOAD_DIR}" ]]; then
    logError "DOWNLOAD_DIR is not set"
    return 1
  elif [[ ! -d "${DOWNLOAD_DIR}" ]]; then
    if ! mkdir -p "${DOWNLOAD_DIR}"; then
      logError "Failed to create DOWNLOAD_DIR at ${DOWNLOAD_DIR}"
      return 1
    fi
  fi

  local arch
  arch=$(uname -m)
  if [[ "${arch}" != "x86_64" ]]; then
    logError "Unsupported architecture for scrcpy static release: ${arch}"
    return 1
  fi

  local release_url
  release_url=$(curl -sL "https://api.github.com/repos/Genymobile/scrcpy/releases/latest" \
    | grep -Eo '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*scrcpy-linux-x86_64-[^"]*\.tar\.gz"' \
    | head -n 1 \
    | cut -d '"' -f 4)

  if [[ -z "${release_url}" ]]; then
    logError "Failed to resolve latest scrcpy release URL"
    return 1
  fi

  local installer location
  installer="$(basename "${release_url}")"
  location="${DOWNLOAD_DIR}/${installer}"

  if [[ ! -f "${location}" ]]; then
    logInfo "Downloading scrcpy release..."
    if ! curl -sSL "${release_url}" -o "${location}"; then
      logError "Failed to download scrcpy release"
      return 1
    fi
  else
    logInfo "Using cached scrcpy release at ${location}"
  fi

  local scrcpy_root="${HOME}/.local/opt/scrcpy"

  rm -rf "${scrcpy_root}"
  mkdir -p "${scrcpy_root}"
  if ! tar -xzf "${location}" -C "${scrcpy_root}" --strip-components=1; then
    logError "Failed to extract scrcpy release"
    return 1
  fi

  # Ensure scrcpy is available on PATH
  mkdir -p "${HOME}/.local/bin"
  ln -sf "${scrcpy_root}/scrcpy" "${HOME}/.local/bin/scrcpy"
  ln -sf "${scrcpy_root}/adb" "${HOME}/.local/bin/adb"

  if ! command -v scrcpy &>/dev/null; then
    logError "scrcpy is not available on PATH after installation"
    return 1
  fi

  logInfo "Android development tools installed successfully"
  return 0
}

# Connect to a phone via ADB over TCP/IP
#
# Parameters:
#   $1: Phone name (for display)
#   $2: DNS name or IP
#   $3: Port (default: 5555)
#   $4: USB serial (optional, for fallback)
# Returns:
#   0: Success
#   1: Failure
adb_connect() {
  local phone_name="$1"
  local phone_dns="$2"
  local phone_port="${3:-5555}"
  local phone_serial="${4:-}"

  # Check if adb is installed
  if ! command -v adb &>/dev/null; then
    logError "adb not found, please install Android Platform Tools"
    return 1
  fi

  logInfo "Connecting to ${phone_name} at ${phone_dns}:${phone_port}..."
  adb connect "${phone_dns}:${phone_port}" &>/dev/null

  # Check if TCP/IP connection worked
  if ! adb devices | grep -w "device" | grep -q "${phone_dns}:${phone_port}"; then
    logWarn "TCP/IP connection failed"

    if [[ -n "${phone_serial}" ]]; then
      logInfo "Checking for USB connection..."

      # Check if device is connected via USB
      if adb devices | grep -w "device" | grep -q "${phone_serial}"; then
        logInfo "Found device via USB (${phone_serial}), enabling TCP/IP mode on port ${phone_port}..."
        adb -s "${phone_serial}" tcpip "${phone_port}"

        logInfo "Waiting for device to restart in TCP/IP mode..."
        sleep 3

        logInfo "Connecting to ${phone_dns}:${phone_port}..."
        adb connect "${phone_dns}:${phone_port}"

        # Check if it worked
        if ! adb devices | grep -w "device" | grep -q "${phone_dns}:${phone_port}"; then
          logError "Failed to connect via TCP/IP after enabling it"
          return 1
        fi
      else
        logError "Device ${phone_name} is not connected via USB or TCP/IP"
        return 1
      fi
    else
      logError "Device ${phone_name} is not connected and no USB serial provided"
      return 1
    fi
  fi

  logInfo "Connected to ${phone_name}"
  return 0
}

# Start scrcpy for a phone
#
# Parameters:
#   $1: Phone name (for display)
#   $2: DNS name or IP with port (e.g., "phone.local:5555")
#   $@: Additional scrcpy arguments
# Returns:
#   0: Success
#   1: Failure
scrcpy_start() {
  local phone_name="$1"
  local phone_address="$2"
  shift 2

  # Check if scrcpy is installed
  if ! command -v scrcpy &>/dev/null; then
    logError "scrcpy not found, please install scrcpy"
    return 1
  fi

  logInfo "Starting scrcpy for ${phone_name}..."
  scrcpy --serial "${phone_address}" "$@" &

  return 0
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
PH_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${PH_SOURCE}" ]]; do # resolve $PH_SOURCE until the file is no longer a symlink
  PH_ROOT=$(cd -P "$(dirname "${PH_SOURCE}")" >/dev/null 2>&1 && pwd)
  PH_SOURCE=$(readlink "${PH_SOURCE}")
  [[ ${PH_SOURCE} != /* ]] && PH_SOURCE=${PH_ROOT}/${PH_SOURCE} # if $PH_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
PH_ROOT=$(cd -P "$(dirname "${PH_SOURCE}")" >/dev/null 2>&1 && pwd)

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
