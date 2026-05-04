# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Helpers for Blu-ray support

if [[ -z ${GUARD_BLURAY_SH+x} ]]; then
  GUARD_BLURAY_SH=1
else
  return 0
fi

vlc_install() {
  logInfo "Installing VLC media player for Blu-ray support"

  if ! pkg_install "vlc"; then
    logError "Failed to install VLC media player"
    return 1
  else
    logDebug "Successfully installed VLC media player"
  fi

  return 0
}

vlc_add_blu_ray_support() {
  logInfo "Adding Blu-ray support to VLC media player"

  if ! pkg_install "libbluray2" "libaacs0" "libbdplus0" "libbluray-bdj"; then
    logError "Failed to install AACS and BD+ libraries for Blu-ray support"
    return 1
  elif ! vlc_update_keys; then
    logError "Failed to update VLC keys for Blu-ray support"
    return 1
  elif ! vlc_add_java; then
    logError "Failed to add Java support for BD-J in VLC media player"
    return 1
  elif ! xdg_optical_autorun; then
    logError "Failed to install optical media autorun script for VLC media player"
    return 1
  else
    logDebug "Successfully added Blu-ray support to VLC media player"
  fi

  return 0
}

vlc_add_java() {
  logInfo "Adding Java support to VLC media player for Blu-ray support"

  if ! command -v java >/dev/null 2>&1; then
    logWarn "Java is not installed, needed for BD-J support in VLC media player"
    if ! pkg_install "openjdk-17-jre"; then
      logError "Failed to install OpenJDK Java runtime for BD-J support in VLC media player"
      return 1
    else
      logDebug "Successfully installed OpenJDK Java runtime for BD-J support in VLC media player"
    fi
  fi

  # Construct JAVA_HOME path
  local java_home
  local java_path
  if ! java_path=$(command -v java); then
    logError "Failed to find Java executable for BD-J support in VLC media player"
    return 1
  else
    logDebug "Successfully added Java support to VLC media player for Blu-ray support"
  fi

  # Check if we have a simlink. If so, resolve it
  if [[ -L "${java_path}" ]]; then
    if ! java_path=$(readlink -f "${java_path}"); then
      logError "Failed to resolve Java executable path for BD-J support in VLC media player"
      return 1
    else
      logDebug "Successfully resolved Java executable path for BD-J support in VLC media player"
    fi
  fi

  java_home=$(dirname "$(dirname "${java_path}")")
  logInfo "Configuring JAVA_HOME to \"${java_home}\" for BD-J support in VLC media player"

  # Add JAVA_HOME to global environment
  local file_ct
  file_ct=$(
    cat <<EOF
# Installed by jeremfg/setup src/bluray.sh to add Java support for BD-J in VLC media player
export JAVA_HOME="${java_home}"
export PATH="\${JAVA_HOME}/bin:\${PATH}"
EOF
  )

  local env_file="/etc/profile.d/vlc-bluray-java.sh"
  # shellcheck disable=SC1090
  if ! echo "${file_ct}" | sudo tee "${env_file}" >/dev/null; then
    logError "Failed to create environment variable file for Java support in VLC media player at ${env_file}"
    return 1
  elif ! sudo chmod 644 "${env_file}"; then
    logError "Failed to set permissions for environment variable file for Java support in VLC media player at ${env_file}"
    return 1
  elif ! source "${env_file}"; then
    logError "Failed to source environment variable file for Java support in VLC media player at ${env_file}"
    return 1
  else
    logDebug "Successfully added Java support to VLC media player for Blu-ray support"
  fi

  # Confirm that JAVA_HOME is set correctly
  if [[ -z "${JAVA_HOME}" ]]; then
    logError "JAVA_HOME is not set after adding Java support to VLC media player for Blu-ray support"
    return 1
  elif [[ "${JAVA_HOME}" != "${java_home}" ]]; then
    logError "JAVA_HOME is set to ${JAVA_HOME} but expected ${java_home}"
    return 1
  else
    logDebug "JAVA_HOME is set correctly to ${JAVA_HOME} after adding Java support to VLC media player for Blu-ray support"
  fi

  return 0
}

vlc_update_keys() {
  logInfo "Updating KEYSDB.cfg for VLC Blu-ray support"
  local keysdb_path="/usr/share/aacs/KEYDB.cfg"
  local keysdb_url="https://vlc-bluray.whoknowsmy.name/files/KEYDB.cfg"

  if ! command -v wget >/dev/null 2>&1; then
    logError "wget is not installed, cannot update KEYSDB.cfg for VLC Blu-ray support"
    return 1
  elif ! sudo mkdir -p "$(dirname "${keysdb_path}")"; then
    logError "Failed to create directory for KEYSDB.cfg at $(dirname "${keysdb_path}")"
    return 1
  elif ! sudo wget -qO "${keysdb_path}" "${keysdb_url}"; then
    logError "Failed to download KEYSDB.cfg from ${keysdb_url}"
    return 1
  elif ! sudo sed -i '1s/^\xEF\xBB\xBF//' "${keysdb_path}"; then
    logError "Failed to remove BOM from KEYSDB.cfg at ${keysdb_path}"
    return 1
  elif ! sudo chmod 644 "${keysdb_path}"; then
    logError "Failed to set permissions for KEYSDB.cfg at ${keysdb_path}"
    return 1
  else
    logInfo "Successfully updated KEYSDB.cfg for VLC Blu-ray support"
  fi

  return 0
}

makemkv_install() {
  logInfo "Installing MakeMKV for Blu-ray support"

  if ! pkg_add_ppa "ppa:heyarje/makemkv-beta"; then
    logError "Failed to add MakeMKV PPA repository"
    return 1
  elif ! pkg_install "makemkv-bin" "makemkv-oss"; then
    logError "Failed to install MakeMKV packages"
    return 1
  else
    logDebug "Successfully installed MakeMKV for Blu-ray support"
  fi

  logInfo <<EOF
You will need to update the MakeMKV licence key periodically.
See https://forum.makemkv.com/forum/viewtopic.php?f=5&t=1053
EOF

  return 0
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
BD_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${BD_SOURCE}" ]]; do # resolve $BD_SOURCE until the file is no longer a symlink
  BD_ROOT=$(cd -P "$(dirname "${BD_SOURCE}")" >/dev/null 2>&1 && pwd)
  BD_SOURCE=$(readlink "${BD_SOURCE}")
  [[ ${BD_SOURCE} != /* ]] && BD_SOURCE=${BD_ROOT}/${BD_SOURCE} # if $BD_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
BD_ROOT=$(cd -P "$(dirname "${BD_SOURCE}")" >/dev/null 2>&1 && pwd)
BD_ROOT=$(realpath "${BD_ROOT}/..")

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
elif ! source "${BD_ROOT}/src/pkg.sh"; then
  logFatal "Failed to import pkg.sh"
elif ! source "${BD_ROOT}/src/file.sh"; then
  logFatal "Failed to import file.sh"
elif ! source "${BD_ROOT}/src/xdg.sh"; then
  logFatal "Failed to import xdg.sh"
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
