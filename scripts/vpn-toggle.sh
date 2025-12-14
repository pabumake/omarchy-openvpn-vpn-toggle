#!/bin/bash
set -eEo pipefail

# Source VPN configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/vpn.conf"

# PID file to track OpenVPN process
PID_FILE="${SCRIPT_DIR}/vpn.pid"

# Check if VPN is running
if [[ -f "${PID_FILE}" ]] && ps -p $(cat "${PID_FILE}") > /dev/null 2>&1; then
  # VPN is running, stop it
  echo "Stopping VPN..."
  sudo kill $(cat "${PID_FILE}")
  rm -f "${PID_FILE}"
  # Clean up auth file
  rm -f "${SCRIPT_DIR}"/.vpn_auth_*
  echo "VPN disconnected"
else
  # VPN is not running, start it
  config_file="${VPN_CONFIG_PATH}"
  
  if ! sudo test -f "${config_file}"; then
    echo "Error: Config file not found: ${config_file}"
    exit 1
  fi
  
  # Check if credentials are needed
  if [[ -z "${VPN_USER}" ]] || [[ -z "${VPN_PASSWORD}" ]]; then
    echo "Error: VPN_USER and VPN_PASSWORD must be set in vpn.conf"
    echo "Please run the selection menu (Right-click) to configure credentials."
    exit 1
  fi
  
  echo "Starting VPN..."
  
  # Create temporary auth file
  auth_file="${SCRIPT_DIR}/.vpn_auth_${VPN_NAME}"
  echo "${VPN_USER}" > "${auth_file}"
  echo "${VPN_PASSWORD}" >> "${auth_file}"
  chmod 600 "${auth_file}"
  
  # Start OpenVPN with auth file
  sudo openvpn --config "${config_file}" --auth-user-pass "${auth_file}" --daemon
  
  # Wait a moment for openvpn to start, then get its PID
  sleep 1
  openvpn_pid=$(pgrep -o -f "openvpn.*$(basename "${config_file}")")
  if [[ -n "${openvpn_pid}" ]]; then
    echo "${openvpn_pid}" > "${PID_FILE}"
    echo "VPN connection initiated"
  else
    echo "Failed to start VPN"
    rm -f "${auth_file}"
    exit 1
  fi
fi
