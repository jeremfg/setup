# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Utilities to confgure a Zentyal server

if [[ -z ${GUARD_ZL_SH+x} ]]; then
  GUARD_ZL_SH=1
else
  return 0
fi

# Configure replication with PDC
# Parameters:
#   $1[in]: The PDC FQDN
#   $2[in]: The PDC username
#   $3[in]: The PDC password
#   $4[in]: The PDC name
#   $5[in]: The BDC name
zl_configure_replication() {
  local __pdc_fqdn="${1}"
  local __pdc_user="${2}"
  local __pdc_pwd="${3}"
  local __pdc_name="${4}"
  local __bdc_name="${5}"

  logInfo "Establishing authentication with PDC"

  # Generate an identify for SSH
  local zl_local_key
  if ! ssh_identity_create zl_local_key; then
    logError "Failed to create SSH identity"
    return 1
  fi
  # Get authorized on the PDC
  if ! ssh_identity_authorize "${zl_local_key}" "${__pdc_user}" "${__pdc_pwd}" "${__pdc_fqdn}" "22"; then
    logError "Failed to authorize SSH key on PDC"
    return 1
  fi

  if ! _sysvol_setup "${__pdc_fqdn}" "${__pdc_name}" "${__bdc_name}" "${__pdc_user}"; then
    logError "Failed to configure LDAP replication"
    return 1
  elif ! _sysvol_cron; then
    logError "Failed to configure SYSVOL replication cron job"
    return 1
  fi

  # Perform an initial replication to ensure everything is working
  if ! sudo dash "${ZL_REPL_SCRIPT}"; then
    logError "Failed to perform replication"
    return 1
  fi

  # Restart samba
  if ! sudo systemctl restart samba-ad-dc; then
    logError "Failed to restart samba"
    return 1
  fi

  logInfo "Replication configured successfully"
}

_sysvol_cron() {
  local job=$(cat <<EOF
0 * * * * root ${ZL_REPL_SCRIPT} >> ${ZL_REPL_LOG} 2>&1
EOF
)
  if ! echo "${job}" | sudo tee "${ZL_CRON_DEF}" >/dev/null; then
    logError "Failed to write cron definition"
    return 1
  elif ! sudo chmod 644 "${ZL_CRON_DEF}"; then
    logError "Failed to set permissions on cron definition"
    return 1
  elif ! sudo chown root:root "${ZL_CRON_DEF}"; then
    logError "Failed to set ownership on cron definition"
    return 1
  else
    logInfo "Cron job for replication created successfully"
  fi

  return 0
}

# Setup SYSVOL replication
# Parameters:
#   $1[in]: The PDC FQDN
#   $2[in]: The PDC name
#   $3[in]: The BDC name
#   $4[in]: The PDC user (for SSH)
_sysvol_setup() {
  local __spdc_fqdn="${1}"
  local __spdc_name="${2}"
  local __sbdc_name="${3}"
  local __spdc_user="${4}"

  logInfo "Setting up SYSVOL replication"

  # Retrieve the list of objects to sync
  local dc_objects
  if ! readarray -t dc_objects < <(sudo samba-tool drs showrepl 2>/dev/null | grep -E '^CN=|^DC=' | sort -u); then
    logError "Failed to retrieve domain objects for replication"
    return 1
  elif [[ ${#dc_objects[@]} -ne 5 ]]; then
    logError "Expected 5 domain objects for replication, found ${#dc_objects[@]}"
    return 1
  fi

  # Make sure we have the identity file
  if [[ -z ${SSH_IDENTITY_KEY} ]]; then
    logError "SSH identity key is not set"
    return 1
  elif [[ ! -f ${SSH_IDENTITY_KEY} ]]; then
    logError "SSH identity key not found at ${SSH_IDENTITY_KEY}"
    return 1
  fi

  # Prepare replication file
  local cur_obj repl_code cur_step
  local replication_steps=""
  for cur_obj in "${dc_objects[@]}"; do
    cur_step="${ZL_REPLICATION_STEP//@SRC_DC@/'${PDC_NAME}'}"
    cur_step="${cur_step//@DST_DC@/'${BDC_NAME}'}"
    cur_step="${cur_step//@OBJECT@/${cur_obj}}"
    replication_steps+="${cur_step}"
  done
  for cur_obj in "${dc_objects[@]}"; do
    cur_step="${ZL_REPLICATION_STEP//@SRC_DC@/'${BDC_NAME}'}"
    cur_step="${cur_step//@DST_DC@/'${PDC_NAME}'}"
    cur_step="${cur_step//@OBJECT@/${cur_obj}}"
    replication_steps+="${cur_step}"
  done

  repl_code="${ZL_REPLICATION_SCRIPT//@PDC_FQDN@/${__spdc_fqdn}}"
  repl_code="${repl_code//@PDC_USER@/${__spdc_user}}"
  repl_code="${repl_code//@PDC_NAME@/${__spdc_name}}"
  repl_code="${repl_code//@BDC_NAME@/${__sbdc_name}}"
  repl_code="${repl_code//@SSH_IDENTITY_KEY@/${SSH_IDENTITY_KEY}}"
  repl_code="${repl_code//@REPLICATION_STEPS@/${replication_steps}}"

  # Write replication file
  if ! echo "${repl_code}" | sudo tee "${ZL_REPL_SCRIPT}" >/dev/null; then
    logError "Failed to write replication script"
    return 1
  elif ! sudo chmod 750 "${ZL_REPL_SCRIPT}"; then
    logError "Failed to make replication script executable"
    return 1
  elif ! sudo chown root:root "${ZL_REPL_SCRIPT}"; then
    logError "Failed to change replication script ownership to root"
    return 1
  fi

  logInfo "SYSVOL replication configured successfully"
}

ZL_REPLICATION_SCRIPT=$(cat <<'EOF'
# !/bin/env sh
# SPDX-License-Identifier: MIT
#
# This script performs replication with the PDC.
# It was installed by jeremfg/setup zentyal.sh and should be executed by cron

LOGGER_NAME="zentyal-replication"
PDC_FQDN="@PDC_FQDN@"
PDC_NAME="@PDC_NAME@"
BDC_NAME="@BDC_NAME@"
PDC_USER="@PDC_USER@"
SYSVOL_PATH="/var/lib/samba/sysvol/"

perform_replication() {
  if ! object_replication; then
    logger -t "${LOGGER_NAME}" "Object replication failed"
    return 1
  elif ! sysvol_replication; then
    logger -t "${LOGGER_NAME}" "SYSVOL replication failed"
    return 1
  fi
}

sysvol_replication() {
  logger -t "${LOGGER_NAME}" "Starting SYSVOL replication with ${PDC_FQDN}"

  # Rsync arguments:
  set -- sudo rsync -aAXH --delete --numeric-ids --rsync-path="sudo rsync-wrapper"

  # SSH arguments:
  set -- "${@}" -e "ssh -o StrictHostKeyChecking=no -i @SSH_IDENTITY_KEY@"

  # Copy arguments:
  set -- "${@}" "${PDC_USER}@${PDC_FQDN}:${SYSVOL_PATH}" "${SYSVOL_PATH}"

  if ! "${@}"; then
    logger -t "${LOGGER_NAME}" "Failed to replicate SYSVOL from ${PDC_FQDN}"
    return 1
  elif ! sudo samba-tool ntacl sysvolreset; then
    logger -t "${LOGGER_NAME}" "Failed to reset SYSVOL ACLs after replication"
    return 1
  else
    logger -t "${LOGGER_NAME}" "SYSVOL replication with ${PDC_FQDN} completed successfully"
  fi

  return 0
}

object_replication() {
  if false; then
    :@REPLICATION_STEPS@
  else
    logger -t "${LOGGER_NAME}" "Object Replication Successful"
  fi

  return 0
}

# Force replication for the given object
# Parameters:
#   $1[in]: Source DC (e.g. "DC1")
#   $2[in]: Destination DC (e.g. "NSSDC")
#   $3[in]: The object to replicate (e.g. "CN=Schema,CN=Configuration,DC=ad,DC=jeremfg,DC=com")
replicate_object() {
  _src_dc="${1}"
  _dst_dc="${2}"
  _object="${3}"

  if [ -z "${_src_dc}" ] || [ -z "${_dst_dc}" ]; then
    logger -t "${LOGGER_NAME}" "Source and destination DCs must be provided"
    return 1
  elif [ -z "${_object}" ]; then
    logger -t "${LOGGER_NAME}" "No object provided for replication"
    return 1
  else
    logger -t "${LOGGER_NAME}" "Forcing replication for ${_object}"
  fi

  if ! sudo samba-tool drs replicate "${_dst_dc}" "${_src_dc}" "${_object}" --full-sync >/dev/null 2>&1; then
    logger -t "${LOGGER_NAME}" "Failed to force replication for ${_object}"
    return 1
  else
    logger -t "${LOGGER_NAME}" "Replication for ${_object} forced successfully"
    return 0
  fi
}

logger -t "${LOGGER_NAME}" "Starting replication script"
if ! perform_replication; then
  logger -t "${LOGGER_NAME}" "Replication failed"
  exit 1
else
  logger -t "${LOGGER_NAME}" "Replication completed successfully"
fi

exit 0

EOF
)

ZL_REPLICATION_STEP=$(cat <<'EOF'

  elif ! replicate_object @SRC_DC@ @DST_DC@ @OBJECT@; then
    logger -t "${LOGGER_NAME}" "Failed to replicate @OBJECT@ from @SRC_DC@ to @DST_DC@"
    return 1
EOF
)

# Global constants
ZL_REPL_LOG="/var/log/zl_replication.log"
ZL_REPL_SCRIPT="/usr/local/bin/zl_replication.sh"
ZL_CRON_DEF="/etc/cron.d/zl-replication"

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
ZL_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${ZL_SOURCE}" ]]; do # resolve $ZL_SOURCE until the file is no longer a symlink
  ZL_ROOT=$(cd -P "$(dirname "${ZL_SOURCE}")" >/dev/null 2>&1 && pwd)
  ZL_SOURCE=$(readlink "${ZL_SOURCE}")
  [[ ${ZL_SOURCE} != /* ]] && ZL_SOURCE=${ZL_ROOT}/${ZL_SOURCE} # if $ZL_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
ZL_ROOT=$(cd -P "$(dirname "${ZL_SOURCE}")" >/dev/null 2>&1 && pwd)
ZL_ROOT=$(realpath "${ZL_ROOT}/..")

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
elif ! source "${ZL_ROOT}/src/constants.sh"; then
  logFatal "Failed to import constants.sh"
elif ! source "${ZL_ROOT}/src/ssh.sh"; then
  logFatal "Failed to import ssh.sh"
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
