# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Shared helpers for pass initialization

if [[ -z ${GUARD_PASS_SH} ]]; then
  GUARD_PASS_SH=1
else
  return 0
fi

# Ensure pass + gpg are configured for Docker Desktop sign-in
#
# Parameters:
#   $1: Config key name to store the GPG ID (e.g., DOCKER_GPG_ID)
#   $2: Config file path to read/write (e.g., ~/.config/local.env)
pass_setup_gpg() {
  local gpg_key_name="$1"
  local config_file="$2"

  if [[ -z "${gpg_key_name}" || -z "${config_file}" ]]; then
    logError "Missing parameters for pass_setup_gpg"
    return 1
  fi

  # Ensure pass is available
  if ! command -v pass &>/dev/null; then
    logInfo "Installing pass..."
    if ! pkg_install pass; then
      logError "Failed to install pass"
      return 1
    fi
  fi

  if ! command -v gpg &>/dev/null; then
    logInfo "Installing gnupg for pass..."
    if ! pkg_install gnupg; then
      logError "Failed to install gnupg"
      return 1
    fi
  fi

  # Load configuration to get GPG ID (if available)
  local gpg_id=""
  if [[ -n "${gpg_key_name}" ]]; then
    gpg_id="${!gpg_key_name}"
  fi

  # If no GPG ID configured, check existing GPG keys or generate one
  if [[ -z "${gpg_id}" ]]; then
    logInfo "No ${gpg_key_name} configured, checking for existing GPG keys..."

    local gpg_ids
    mapfile -t gpg_ids < <(gpg --list-keys --with-colons 2>/dev/null | awk -F: '/^pub:/ {print $5}')

    if [[ ${#gpg_ids[@]} -gt 1 ]]; then
      logError "Multiple GPG keys found. Set ${gpg_key_name} in ${config_file} to choose one."
      return 1
    elif [[ ${#gpg_ids[@]} -eq 1 ]]; then
      gpg_id="${gpg_ids[0]}"
    else
      logInfo "No GPG keys found, generating a new one..."

        # Fetch user info from git config (required)
        local git_user_name git_user_email
        git_user_name=$(git config user.name 2>/dev/null || true)
        git_user_email=$(git config user.email 2>/dev/null || true)

        if [[ -z "${git_user_name}" || -z "${git_user_email}" ]]; then
          logError "Git user.name and user.email must be set to generate a GPG key"
          logError "Run: git config user.name \"Your Name\""
          logError "Run: git config user.email \"you@example.com\""
          return 1
        fi

        logInfo "Using git identity: ${git_user_name} <${git_user_email}>"

        # Generate GPG key non-interactively using EDDSA (elliptic curve)
        local gpg_batch_file
        gpg_batch_file=$(mktemp)
        cat > "${gpg_batch_file}" << EOF
%echo Generating OpenPGP key
Key-Type: ECDSA
Key-Curve: nistp384
Subkey-Type: ECDH
Subkey-Curve: nistp384
Name-Real: ${git_user_name}
Name-Email: ${git_user_email}
Expire-Date: 0
Preferences: AES256 SHA384 SHA512
%no-protection
%commit
%echo Key generation complete
EOF

        if ! gpg --batch --generate-key "${gpg_batch_file}" 2>&1 | while IFS= read -r line; do logInfo "$line"; done; then
          logError "Failed to generate GPG key"
          rm -f "${gpg_batch_file}"
          return 1
        fi
        rm -f "${gpg_batch_file}"

        # Extract the newly generated key ID
        gpg_id=$(gpg --list-keys --with-colons 2>/dev/null | grep '^pub:' | cut -d: -f5 | head -n 1)

        if [[ -z "${gpg_id}" ]]; then
          logError "Failed to retrieve generated GPG key ID"
          return 1
        fi

      logInfo "Generated GPG key ID: ${gpg_id}"
    fi
  fi

  if [[ -n "${gpg_id}" ]]; then
    # Validate that the key exists locally
    if ! gpg --list-keys "${gpg_id}" &>/dev/null; then
      logError "GPG key not found locally: ${gpg_id}"
      logError "Remove ${gpg_key_name} from ${config_file} or import the key, then retry"
      return 1
    fi

    # Initialize pass if not already done
    if [[ ! -d "${HOME}/.password-store" ]]; then
      logInfo "Initializing pass..."
      if ! pass init "${gpg_id}"; then
        logError "Failed to initialize pass with GPG ID ${gpg_id}"
        return 1
      fi
    fi

    # Save configuration
    logInfo "Updating config with ${gpg_key_name}..."
    if ! config_save "${config_file}" "${gpg_key_name}" "${gpg_id}"; then
      logError "Could not update config. Add manually: ${gpg_key_name}=${gpg_id}"
      return 1
    fi
  else
    logError "Could not determine or generate GPG key for pass initialization"
    return 1
  fi

  return 0
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
PS_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${PS_SOURCE}" ]]; do # resolve $PS_SOURCE until the file is no longer a symlink
  PS_ROOT=$(cd -P "$(dirname "${PS_SOURCE}")" >/dev/null 2>&1 && pwd)
  PS_SOURCE=$(readlink "${PS_SOURCE}")
  [[ ${PS_SOURCE} != /* ]] && PS_SOURCE=${PS_ROOT}/${PS_SOURCE} # if $PS_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
PS_ROOT=$(cd -P "$(dirname "${PS_SOURCE}")" >/dev/null 2>&1 && pwd)
PS_ROOT=$(realpath "${PS_ROOT}/..")

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
elif ! source "${PREFIX}/lib/config.sh"; then
  echo "Failed to import config.sh"
  exit 1
elif ! source "${PS_ROOT}/src/pkg.sh"; then
  echo "Failed to import pkg.sh"
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
