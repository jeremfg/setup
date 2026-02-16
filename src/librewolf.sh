#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# Guard to prevent multiple sourcing
[[ -n "${GUARD_LIBREWOLF_SH+x}" ]] && return 0
readonly GUARD_LIBREWOLF_SH=1

############################################
## Configuration
############################################

LIBREWOLF_PROFILE_BASE="${HOME}/.librewolf"
LIBREWOLF_PROFILES_INI="${LIBREWOLF_PROFILE_BASE}/profiles.ini"

# Install Librewolf browser and configure it
librewolf_install() {
  logInfo "Installing Librewolf..."

  # Install Librewolf via extrepo (per https://librewolf.net/installation/debian/)
  if ! extrepo_install_package librewolf librewolf; then
    logError "Failed to install Librewolf"
    return 1
  fi

  logInfo "Librewolf installed successfully"
  return 0
}

# Configure browser.profiles.enabled in user.js
_librewolf_configure_profiles_enabled() {
  if [[ ! -f "${LIBREWOLF_PROFILES_INI}" ]]; then
    logInfo "Enabling multi-profile support..."
    if ! file_ensure_dir "${LIBREWOLF_PROFILE_BASE}"; then
      logError "Failed to create Librewolf profile base: ${LIBREWOLF_PROFILE_BASE}"
      return 1
    fi

    cat > "${LIBREWOLF_PROFILES_INI}" << 'EOF'
[Profile0]
Name=default
IsRelative=1
Path=default
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

    if ! file_ensure_dir "${LIBREWOLF_PROFILE_BASE}/default"; then
      logError "Failed to create Librewolf default profile"
      return 1
    fi
    logInfo "Multi-profile support enabled"
  else
    logInfo "Multi-profile support already configured"
  fi

  if ! _librewolf_set_user_pref "browser.profiles.enabled" "true" "// Enable profile management UI"; then
    return 1
  fi

  return 0
}

# Configure Firefox Sync preferences in user.js
_librewolf_configure_sync_enabled() {
  if ! _librewolf_set_user_pref "identity.fxaccounts.enabled" "true" "// Enable Firefox Sync"; then
    return 1
  fi

  return 0
}

# Resolve Profile0 path from profiles.ini
#
# Parameters:
#   $1[out]: Absolute profile path
_librewolf_profile0_path() {
  local __out="$1"

  if [[ ! -f "${LIBREWOLF_PROFILES_INI}" ]]; then
    return 1
  fi

  local rel path_line
  path_line=$(awk '
    $0 ~ /^\[Profile0\]$/ {in_profile=1; next}
    in_profile && $1 ~ /^Path=/ {print; exit}
    in_profile && /^\[/ {exit}
  ' "${LIBREWOLF_PROFILES_INI}")
  rel="${path_line#Path=}"

  if [[ -z "${rel}" ]]; then
    return 1
  fi

  if [[ "${rel}" = /* ]]; then
    eval "${__out}='${rel}'"
  else
    eval "${__out}='${LIBREWOLF_PROFILE_BASE}/${rel}'"
  fi

  return 0
}

# Set or update a user.js preference
#
# Parameters:
#   $1[in]: Preference name
#   $2[in]: Preference value (unquoted)
#   $3[in]: Optional comment line
_librewolf_set_user_pref() {
  local pref_name="$1"
  local pref_value="$2"
  local pref_comment="$3"

  local profile_path
  if ! _librewolf_profile0_path profile_path; then
    logWarn "Default profile not found. Preference will be applied on first launch."
    return 0
  fi

  local user_js="${profile_path}/user.js"

  if [[ ! -f "${user_js}" ]]; then
    touch "${user_js}"
  fi

  if grep -q "user_pref(\"${pref_name//./\\.}\",[[:space:]]*${pref_value});" "${user_js}"; then
    logInfo "${pref_name} already set"
    return 0
  fi

  if grep -q "${pref_name//./\\.}" "${user_js}"; then
    if ! sed -i "s/user_pref(\"${pref_name//./\\.}\",[[:space:]]*[^)]*);/user_pref(\"${pref_name}\", ${pref_value});/" "${user_js}"; then
      logError "Failed to update ${pref_name} in ${user_js}"
      return 1
    fi
    logInfo "${pref_name} updated in profile"
    return 0
  fi

  if [[ -n "${pref_comment}" ]]; then
    printf '\n%s\n' "${pref_comment}" >>"${user_js}"
  else
    printf '\n' >>"${user_js}"
  fi
  printf 'user_pref("%s", %s);\n' "${pref_name}" "${pref_value}" >>"${user_js}"
  logInfo "${pref_name} set in profile"
  return 0
}

# Configure Librewolf as default browser
_librewolf_configure_default_browser() {
  if ! command -v xdg-settings &>/dev/null; then
    logWarn "xdg-settings not found; cannot set default browser"
    return 0
  fi

  if ! xdg-settings set default-web-browser librewolf.desktop; then
    logError "Failed to set Librewolf as default browser"
    return 1
  fi

  logInfo "Librewolf set as default browser"
  return 0
}

# Configure Librewolf for multi-profile support and Firefox Sync
librewolf_configure() {
  logInfo "Configuring Librewolf..."

  if ! _librewolf_configure_profiles_enabled; then
    return 1
  fi

  if ! _librewolf_configure_sync_enabled; then
    return 1
  fi

  if ! _librewolf_configure_default_browser; then
    return 1
  fi

  logInfo "Librewolf configuration complete"
  return 0
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
LW_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${LW_SOURCE}" ]]; do # resolve $LW_SOURCE until the file is no longer a symlink
  LW_ROOT=$(cd -P "$(dirname "${LW_SOURCE}")" >/dev/null 2>&1 && pwd)
  LW_SOURCE=$(readlink "${LW_SOURCE}")
  [[ ${LW_SOURCE} != /* ]] && LW_SOURCE=${LW_ROOT}/${LW_SOURCE} # if $LW_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
LW_ROOT=$(cd -P "$(dirname "${LW_SOURCE}")" >/dev/null 2>&1 && pwd)

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
elif ! source "${LW_ROOT}/extrepo.sh"; then
  logFatal "Failed to import extrepo.sh"
elif ! source "${LW_ROOT}/file.sh"; then
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
