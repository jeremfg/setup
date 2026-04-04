# !/bin/env sh
# SPDX-License-Identifier: MIT
#
# LightDM GUI takeover logic for xRDP sessions
# This script should have no dependencies beyond BPKG to run
# This script is typically installed automatically by xrdp.sh
#
# This is needed because cinammon doesn't support opening more than one
# session per user, and LightDM doesn't support starting a session on the
# same seat as an existing session. This script will kill the local session
# if it exists, allowing xRDP to start a new session on the same seat.

dm_cleanup() {
  logger -t cleanup-sessions "INFO: Cleaning up local sessions for xRDP compatibility"

  # Determine username to check for local sessions
  if [ -n "${PAM_USER}" ]; then
    # Running from xRDP startwm.sh
    cur_user="${PAM_USER}"
  elif [ -n "${LIGHTDM_USER}" ]; then
    # Running from LightDM session-setup-script
    cur_user="${LIGHTDM_USER}"
  else
    cur_user="${USER}"
    logger -t cleanup-sessions "DEBUG: Determined current user for session cleanup: ${cur_user}"
  fi

  # Loop on all sessions for this user
  for cur_session in $(loginctl list-sessions --no-legend | awk -v u="$cur_user" '$3==u && $6=="user" {print $1}'); do
    session_info=$(loginctl show-session "${cur_session}")
    logger -t cleanup-sessions <<EOF
Checking session ${cur_session} for user ${cur_user}

${session_info}
EOF

    # Check Session ID, to not kill ourselves
    session_id=$(echo "${session_info}" | awk -F= '/^Id=/ {print $2}')
    if [ "${session_id}" = "${XDG_SESSION_ID}" ]; then
      logger -t cleanup-sessions "INFO: Skipping current session ${session_id} for user ${cur_user}"
      continue
    fi

    # Check session type
    session_type=$(echo "${session_info}" | awk -F= '/^Type=/ {print $2}')
    if [ "${session_type}" = "x11" ]; then
      logger -t cleanup-sessions "INFO: Terminating local session ${cur_session} of type ${session_type} for user ${cur_user}"
      if ! loginctl terminate-session "${cur_session}"; then
        logger -t cleanup-sessions "ERROR: Failed to terminate session ${cur_session} for user ${cur_user}"
      else
        logger -t cleanup-sessions "DEBUG: Successfully terminated session ${cur_session} for user ${cur_user}"
      fi
    elif [ "${session_type}" = "tty" ]; then
      logger -t cleanup-sessions "INFO: Skipping local session ${cur_session} of type ${session_type} for user ${cur_user}"
    else
      logger -t cleanup-sessions "WARN: Unknown session type ${session_type} for session ${cur_session} of user ${cur_user}, skipping"
    fi
  done

  return 0
}

###########################
###### Startup logic ######
###########################

dm_cleanup "${@}"
exit $?
