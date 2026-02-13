#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# Guard to prevent multiple sourcing
[[ -n "${GUARD_LIBREWOLF_SH}" ]] && return 0
readonly GUARD_LIBREWOLF_SH=1

# Globals
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
    mkdir -p "${LIBREWOLF_PROFILE_BASE}"

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

    mkdir -p "${LIBREWOLF_PROFILE_BASE}/default"
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
