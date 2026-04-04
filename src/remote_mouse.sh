# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# Remote Mouse support
# https://www.remotemouse.net

rm_inst_dir="/opt/RemoteMouse"
rm_exec="${rm_inst_dir}/RemoteMouse"
rm_symlink="/usr/local/bin/remotemouse"
rm_service_file="/etc/systemd/system/remotemouse.service"

rm_install_ubuntu_cinammon() {
  logInfo "Installing Remote Mouse server"

  if ! _rm_install_rm_ubuntu; then
    logError "Failed to install Remote Mouse server"
    return 1
  elif ! _rm_install_srv_ubuntu_cinammon; then
    logError "Failed to setup Remote Mouse server"
    return 1
  else
    logDebug "Successfully installed Remote Mouse server"
  fi

  return 0
}

_rm_install_srv_ubuntu_cinammon() {
  local service_content=$(cat <<EOF
[Unit]
Description=Remote Mouse Server
After=lightdm.service

[Service]
Type=simple
User=root
Group=root

# Execute
ExecStart=${rm_symlink}
Restart=always

# Ensure lightdm has fully started
ExecStartPre=/bin/sleep 2

# Allow GUI interaction
Environment=DISPLAY=:0
Environment=XAUTHORITY=/var/run/lightdm/root/:0
# Environment=XDG_RUNTIME_DIR=/run/user/$(id -u lightdm)

[Install]
WantedBy=multi-user.target
EOF
)

  if ! echo "${service_content}" | sudo tee "${rm_service_file}" >/dev/null; then
    logError "Failed to create Remote Mouse systemd service file at ${rm_service_file}"
    return 1
  elif ! sudo systemctl daemon-reload; then
    logError "Failed to reload systemd daemon after creating Remote Mouse service"
    return 1
  elif ! sudo systemctl enable remotemouse.service; then
    logError "Failed to enable Remote Mouse systemd service"
    return 1
  elif ! sudo systemctl restart remotemouse.service; then
    logError "Failed to restart Remote Mouse systemd service"
    return 1
  else
    logDebug "Successfully set up Remote Mouse systemd service"
  fi

  return 0
}

_rm_install_rm_ubuntu() {
  # Check if Remote Mouse server is already installed
  if [[ ! -f "${rm_exec}" ]]; then
    local dl_url="https://www.remotemouse.net/downloads/linux/RemoteMouse_x86_64.zip"
    local tmp_dir
    if ! tmp_dir=$(mktemp -d); then
      logError "Failed to create temporary directory for Remote Mouse installation"
      return 1
    fi
    local zip_path="${tmp_dir}/RemoteMouse.zip"
    if ! wget -qO "${zip_path}" "${dl_url}"; then
      logError "Failed to download Remote Mouse server from ${dl_url}"
      sudo rm -rf "${tmp_dir}"
      return 1
    fi
    if ! file_ensure_dir "${rm_inst_dir}"; then
      logError "Failed to create installation directory ${rm_inst_dir} for Remote Mouse server"
      sudo rm -rf "${tmp_dir}"
      return 1
    fi
    if ! sudo unzip -q "${zip_path}" -d "${rm_inst_dir}"; then
      logError "Failed to unzip Remote Mouse server from ${zip_path}"
      sudo rm -rf "${tmp_dir}"
      return 1
    fi
    if ! sudo rm -rf "${tmp_dir}"; then
      logError "Failed to remove temporary directory ${tmp_dir} after Remote Mouse installation"
      return 1
    fi
    if [[ ! -f "${rm_exec}" ]]; then
      logError "Remote Mouse server executable not found at ${rm_exec} after installation"
      sudo rm -rf "${rm_inst_dir}"
      return 1
    fi
    # Make sure the executable has the correct permissions
    if ! sudo chmod +x "${rm_exec}"; then
      logError "Failed to set executable permissions for Remote Mouse server at ${rm_exec}"
      sudo rm -rf "${rm_inst_dir}"
      return 1
    fi
    # Make sure we can invoke the install script
    local install_script="${rm_inst_dir}/install.sh"
    if [[ ! -f "${install_script}" ]]; then
      logError "Remote Mouse server install script not found at ${install_script}"
      sudo rm -rf "${rm_inst_dir}"
      return 1
    elif ! sudo chmod +x "${install_script}"; then
      logError "Failed to set executable permissions for Remote Mouse server install script at ${install_script}"
      sudo rm -rf "${rm_inst_dir}"
      return 1
    elif ! sudo "${install_script}"; then
      logError "Failed to execute Remote Mouse server install script at ${install_script}"
      sudo rm -rf "${rm_inst_dir}"
      return 1
    fi
    logInfo "Successfully installed Remote Mouse server at ${rm_exec}"
  else
    logDebug "Remote Mouse server is already installed at ${rm_exec}, skipping installation"
  fi

  # Make sure the symlink is configured
  if [[ -L "${rm_symlink}" ]]; then
    local target
    if ! target=$(readlink -f "${rm_symlink}"); then
      logError "Failed to read existing symlink for Remote Mouse server at ${rm_symlink}"
      return 1
    elif [[ "${target}" != "${rm_exec}" ]]; then
      logError "Existing symlink for Remote Mouse server at ${rm_symlink} points to ${target} instead of ${rm_exec}"
      return 1
    else
      logDebug "Symlink for Remote Mouse server at ${rm_symlink} is already correctly configured, skipping"
    fi
  elif [[ -e "${rm_symlink}" ]]; then
    logError "Path for Remote Mouse server symlink at ${rm_symlink} exists but is not a symlink"
    return 1
  elif ! sudo ln -s "${rm_exec}" "${rm_symlink}"; then
    logError "Failed to create symlink for Remote Mouse server from ${rm_symlink} to ${rm_exec}"
    return 1
  else
    logInfo "Successfully created symlink for Remote Mouse server from ${rm_symlink} to ${rm_exec}"
  fi

  # Configure firewall to allow Remote Mouse server traffic
  if ! sudo ufw allow 1978/tcp; then
    logError "Failed to allow Remote Mouse server traffic through firewall on port 1978/tcp"
    return 1
  elif ! sudo ufw allow 1978/udp; then
    logError "Failed to allow Remote Mouse server traffic through firewall on port 1978/udp"
    return 1
  elif ! sudo ufw reload; then
    logError "Failed to reload firewall after allowing Remote Mouse server traffic through firewall on port 1978"
    return 1
  else
    logDebug "Successfully allowed Remote Mouse server traffic through firewall on port 1978/tcp and 1978/udp"
  fi

  return 0
}

###########################
###### Startup logic ######
###########################

# Get directory of this script
# https://stackoverflow.com/a/246128
RM_SOURCE=${BASH_SOURCE[0]}
while [[ -L "${RM_SOURCE}" ]]; do # resolve $RM_SOURCE until the file is no longer a symlink
  RM_ROOT=$(cd -P "$(dirname "${RM_SOURCE}")" >/dev/null 2>&1 && pwd)
  RM_SOURCE=$(readlink "${RM_SOURCE}")
  [[ ${RM_SOURCE} != /* ]] && RM_SOURCE=${RM_ROOT}/${RM_SOURCE} # if $RM_SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
RM_ROOT=$(cd -P "$(dirname "${RM_SOURCE}")" >/dev/null 2>&1 && pwd)
RM_ROOT=$(realpath "${RM_ROOT}/..")

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
elif ! source "${RM_ROOT}/src/file.sh"; then
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
