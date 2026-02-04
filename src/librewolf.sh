#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# Guard to prevent multiple sourcing
[[ -n "${GUARD_LIBREWOLF_SH}" ]] && return 0
readonly GUARD_LIBREWOLF_SH=1

# Install Librewolf browser and configure it
librewolf_install() {
  logInfo "Installing Librewolf..."

  # Install dependencies
  if ! pkg_install apt-transport-https; then
    logError "Failed to install apt-transport-https"
    return 1
  fi

  # Add Librewolf repository GPG key
  if ! sudo wget -qO /usr/share/keyrings/librewolf.gpg https://deb.librewolf.net/keyring.gpg; then
    logError "Failed to download Librewolf GPG key"
    return 1
  fi

  # Add Librewolf repository
  local distro codename
  distro=$(grep -E '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
  codename=$(grep -E '^VERSION_CODENAME=' /etc/os-release | cut -d'=' -f2)

  # Librewolf only supports Ubuntu/Debian directly
  if [[ "${distro}" == "linuxmint" ]]; then
    # Linux Mint is based on Ubuntu, so use Ubuntu's codename
    codename=$(grep UBUNTU_CODENAME /etc/os-release | cut -d'=' -f2)
  fi

  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/librewolf.gpg] https://deb.librewolf.net ${codename} main" | \
    sudo tee /etc/apt/sources.list.d/librewolf.list > /dev/null

  # Update package list
  if ! sudo apt-get update; then
    logError "Failed to update package list"
    return 1
  fi

  # Install Librewolf
  if ! pkg_install librewolf; then
    logError "Failed to install Librewolf"
    return 1
  fi

  logInfo "Librewolf installed successfully"
  return 0
}

# Configure Librewolf for multi-profile support and Firefox Sync
librewolf_configure() {
  logInfo "Configuring Librewolf..."

  # Determine the Librewolf profile directory
  local profile_base="${HOME}/.librewolf"

  # Create profiles.ini if it doesn't exist (for multi-profile support)
  local profiles_ini="${profile_base}/profiles.ini"

  if [[ ! -f "${profiles_ini}" ]]; then
    logInfo "Enabling multi-profile support..."
    mkdir -p "${profile_base}"

    # Create a basic profiles.ini with the default profile
    cat > "${profiles_ini}" << 'EOF'
[Profile0]
Name=default
IsRelative=1
Path=default
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

    # Create the default profile directory
    mkdir -p "${profile_base}/default"
    logInfo "Multi-profile support enabled"
  else
    logInfo "Multi-profile support already configured"
  fi

  # Enable Firefox Sync by creating user.js in the default profile
  local default_profile="${profile_base}/default"
  local user_js="${default_profile}/user.js"

  if [[ -d "${default_profile}" ]]; then
    logInfo "Enabling Firefox Sync..."

    # Create or append to user.js
    if [[ ! -f "${user_js}" ]]; then
      touch "${user_js}"
    fi

    # Check if Firefox Sync is already enabled
    if ! grep -q "identity.fxaccounts.enabled" "${user_js}"; then
      cat >> "${user_js}" << 'EOF'

// Enable Firefox Sync
user_pref("identity.fxaccounts.enabled", true);
user_pref("identity.sync.tokenserver.uri", "https://token.services.mozilla.com/1.0/sync/1.5");
EOF
      logInfo "Firefox Sync enabled in default profile"
    else
      logInfo "Firefox Sync already enabled"
    fi
  else
    logWarn "Default profile not found. Firefox Sync configuration will be applied on first launch."
  fi

  logInfo "Librewolf configuration complete"
  return 0
}
