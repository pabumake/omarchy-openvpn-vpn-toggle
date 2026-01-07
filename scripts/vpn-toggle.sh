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
  
  if !  test -f "${config_file}"; then
    echo "Error: Config file not found: ${config_file}"
    exit 1
  fi
  
  # Check if credentials are present
  AUTH_OPTS=()
  auth_file=""
  if [[ -n "${VPN_USER}" ]] && [[ -n "${VPN_PASSWORD}" ]]; then
      # Create temporary auth file
      auth_file="${SCRIPT_DIR}/.vpn_auth_${VPN_NAME}"
      echo "${VPN_USER}" > "${auth_file}"
      echo "${VPN_PASSWORD}" >> "${auth_file}"
      chmod 600 "${auth_file}"
      AUTH_OPTS+=("--auth-user-pass" "${auth_file}")
  else
      echo "No credentials found, attempting specific connection without auth..."
  fi
  
  echo "Starting VPN..."
  
  # Log file for troubleshooting
  LOG_FILE="/tmp/vpn-toggle.log"

  # Create a temporary sanitized config to avoid issues with missing scripts (like update-resolv-conf)
  # process substitution doesn't work well with sudo openvpn sometimes, so using a temp file
  temp_config="${SCRIPT_DIR}/.vpn_config_sanitized_${VPN_NAME}.ovpn"
  # Remove up/down scripts that might be missing, and reference to auth-user-pass in config (we handle it via CLI)
  # We use || true to prevent script exit if grep returns non-zero (though unlikely for -v)
  grep -vE "^\s*(up|down)\s+/etc/openvpn/update-resolv-conf" "${config_file}" | grep -vE "^\s*auth-user-pass" > "${temp_config}" || true

  # Start OpenVPN with auth file
  # Use --writepid to reliably store the PID
  # Use --auth-retry nointeract to prevent hanging if auth fails/missing
  if ! sudo openvpn --config "${temp_config}" \
      "${AUTH_OPTS[@]}" \
      --auth-retry nointeract \
      --daemon \
      --writepid "${PID_FILE}" \
      --log "${LOG_FILE}"; then
      echo "Error: Failed to start OpenVPN process."
      echo "Check permissions or config validity."
      exit 1
  fi
  
  # Wait a moment for openvpn to initialize
  sleep 2
  
  # Check if the process is actually running and connected
  count=0
  connected=false
  while [[ $count -lt 10 ]]; do
    if grep -q "Initialization Sequence Completed" "${LOG_FILE}"; then
        connected=true
        break
    fi
    # Check if process died
    if ! [[ -f "${PID_FILE}" ]] || ! ps -p $(cat "${PID_FILE}") > /dev/null 2>&1; then
      break
    fi
    sleep 1
    count=$((count+1))
  done
  
  if [[ "$connected" = true ]]; then
    echo "VPN connection successful"
    # Show status for Waybar (optional, but good for debugging)
    tail -n 1 "${LOG_FILE}"
    # Cleanup temp config (assuming openvpn has loaded it)
    [[ -f "${temp_config}" ]] && rm -f "${temp_config}"
  else
    echo "Failed to connect to VPN (Timeout or Error). Logic check:"
    echo "Check ${LOG_FILE} for details:"
    if [[ -f "${LOG_FILE}" ]]; then
        # Show the last few lines of errors
        tail -n 10 "${LOG_FILE}"
    fi
    
    # Cleanup: Kill the process if it's still hanging
    if [[ -f "${PID_FILE}" ]]; then
        pid=$(cat "${PID_FILE}")
        if [[ -n "$pid" ]]; then
             sudo kill "$pid" 2>/dev/null || true
        fi
        sudo rm -f "${PID_FILE}"
    fi
    [[ -n "${auth_file}" ]] && rm -f "${auth_file}"
    [[ -f "${temp_config}" ]] && rm -f "${temp_config}"
    exit 1
  fi
fi
