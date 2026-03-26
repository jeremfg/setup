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

  if ! pkg_install "libbluray2" "libaacs0" "libbdplus0"; then
    logError "Failed to install AACS and BD+ libraries for Blu-ray support"
    return 1
  elif ! vlc_update_keys; then
    logError "Failed to update VLC keys for Blu-ray support"
    return 1
  else
    logDebug "Successfully added Blu-ray support to VLC media player"
  fi

  return 0
}

vlc_update_keys() {
  logInfo "Updating KEYSDB.cfg for VLC Blu-ray support"
  local keysdb_path="/etc/xdg/aacs/KEYDB.cfg"
  local keysdb_url="https://vlc-bluray.whoknowsmy.name/files/KEYDB.cfg"

  if ! command -v wget >/dev/null 2>&1; then
    logError "wget is not installed, cannot update KEYSDB.cfg for VLC Blu-ray support"
    return 1
  elif ! file_ensure_dir "$(dirname "${keysdb_path}")"; then
    logError "Failed to create directory for KEYSDB.cfg at $(dirname "${keysdb_path}")"
    return 1
  elif ! sudo wget -qO "${keysdb_path}" "${keysdb_url}"; then
    logError "Failed to download KEYSDB.cfg from ${keysdb_url}"
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
  exit
elif ! source "${BD_ROOT}/src/pkg.sh"; then
  logFatal "Failed to import pkg.sh"
elif ! source "${BD_ROOT}/src/file.sh"; then
  logFatal "Failed to import file.sh"
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
