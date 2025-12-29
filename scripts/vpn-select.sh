#!/bin/bash
set -eEo pipefail

# Configuration
CONFIGS_PATH="${HOME}/.config/openvpn"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/vpn.pid"

# Find available VPN configurations (.ovpn files)
mapfile -t configs < <(find "${CONFIGS_PATH}" -maxdepth 1 -name "*.ovpn" 2>/dev/null | sort)

if [[ ${#configs[@]} -eq 0 ]]; then
  echo "No OpenVPN configurations (.ovpn files) found in ${CONFIGS_PATH}"
  exit 1
fi

# Present a selection menu
echo "Select a VPN configuration (0 to cancel):"
select vpn_config in "${configs[@]}"; do
  # Check if user entered 0 to cancel
  if [[ "${REPLY}" == "0" ]]; then
    echo "Selection cancelled"
    exit 0
  fi
  
  if [[ -n "${vpn_config}" ]]; then
    vpn_name="$(basename "${vpn_config}" .ovpn)"
    # Get the current VPN name
    if [[ -f "${SCRIPT_DIR}/vpn.conf" ]]; then
      source "${SCRIPT_DIR}/vpn.conf"
    fi
    
    config_file="${vpn_config}"
    
    # Check for credentials in comments (format: # VPN_USER=username)
    user=$(sed -n 's/^[#;]\s*VPN_USER=\(.*\)/\1/p' "${config_file}" | head -n 1 | tr -d '\r')
    pass=$(sed -n 's/^[#;]\s*VPN_PASSWORD=\(.*\)/\1/p' "${config_file}" | head -n 1 | tr -d '\r')
    
    if [[ -z "$user" ]]; then
      # Prompt user if not found in config
      echo "Please enter credentials for ${vpn_name}:"
      read -p "Username: " user
      read -s -p "Password: " pass
      echo ""
    else
      echo "Found credentials in config file."
    fi
    
    if [[ -z "$user" ]] || [[ -z "$pass" ]]; then
      echo "Error: Username and password are required."
      exit 1
    fi
    
    # Update vpn.conf with config path and credentials
    cat > "${SCRIPT_DIR}/vpn.conf" <<EOF
VPN_NAME="${vpn_name}"
VPN_CONFIG_PATH="${config_file}"
VPN_USER="${user}"
VPN_PASSWORD="${pass}"
EOF
    echo "VPN configuration updated to ${vpn_name}"

    # If a VPN is connected, disconnect it
    if [[ -f "${PID_FILE}" ]] && ps -p $(cat "${PID_FILE}") > /dev/null 2>&1; then
      echo "Disconnecting current VPN..."
      sudo kill $(cat "${PID_FILE}") 2>/dev/null || true
      rm -f "${PID_FILE}"
      # Clean up old auth files
      rm -f "${SCRIPT_DIR}"/.vpn_auth_*
      
      # Connect to the new VPN
      echo "Connecting to ${vpn_name}..."
      
      # Create temporary auth file
      auth_file="${SCRIPT_DIR}/.vpn_auth_${vpn_name}"
      echo "${user}" > "${auth_file}"
      echo "${pass}" >> "${auth_file}"
      chmod 600 "${auth_file}"
      
      # Start OpenVPN with auth file in daemon mode
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
      fi
    fi
    
    break
  else
    echo "Invalid selection."
  fi
done
