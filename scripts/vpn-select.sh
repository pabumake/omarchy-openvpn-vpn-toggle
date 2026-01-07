#!/bin/bash
set -eEo pipefail

# Configuration
CONFIGS_PATH="${HOME}/.config/openvpn"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/vpn.pid"
CREDS_DIR="${SCRIPT_DIR}/.creds"

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
    
    # Check stored creds if not found in file
    stored_cred_file="${CREDS_DIR}/${vpn_name}.creds"
    if [[ -z "$user" ]] && [[ -f "${stored_cred_file}" ]]; then
         # Read stored
         mapfile -t stored_creds < "${stored_cred_file}"
         s_user="${stored_creds[0]}"
         s_pass="${stored_creds[1]}" 
         
         if [[ -n "$s_user" ]]; then
             echo "Found saved credentials for ${vpn_name} (User: ${s_user})."
             read -p "Use saved credentials? [Y/n]: " use_stored
             use_stored=${use_stored:-Y}
             if [[ "$use_stored" =~ ^[Yy]$ ]]; then
                 user="$s_user"
                 pass="$s_pass"
             fi
         fi
    fi

    if [[ -z "$user" ]]; then
      # Prompt user if not found in config
      echo "Please enter credentials for ${vpn_name} (leave empty to skip):"
      read -p "Username: " user
      if [[ -n "$user" ]]; then
          read -s -p "Password: " pass
          echo ""
      fi
    else
      echo "Using credentials."
    fi
    
    # Save creds if we have them
    if [[ -n "$user" ]]; then
         mkdir -p "${CREDS_DIR}"
         # Save safe permissions
         old_umask=$(umask)
         umask 077
         echo "$user" > "${stored_cred_file}"
         echo "$pass" >> "${stored_cred_file}"
         umask $old_umask
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
      
      AUTH_OPTS=()
      auth_file=""
      if [[ -n "${user}" ]] && [[ -n "${pass}" ]]; then
          # Create temporary auth file
          auth_file="${SCRIPT_DIR}/.vpn_auth_${vpn_name}"
          echo "${user}" > "${auth_file}"
          echo "${pass}" >> "${auth_file}"
          chmod 600 "${auth_file}"
          AUTH_OPTS+=("--auth-user-pass" "${auth_file}")
      fi
      
      # Sanitize config
      temp_config="${SCRIPT_DIR}/.vpn_config_sanitized_${vpn_name}.ovpn"
      # Remove up/down scripts that might be missing, and auth-user-pass lines if we are not providing auth
      # We rely on CLI args for auth if needed.
      grep -vE "^\s*(up|down)\s+/etc/openvpn/update-resolv-conf" "${config_file}" | grep -vE "^\s*auth-user-pass" > "${temp_config}"
      
      # Start OpenVPN with auth file in daemon mode
      # Added --auth-retry nointeract to prevent hanging
      sudo openvpn --config "${temp_config}" "${AUTH_OPTS[@]}" --auth-retry nointeract --daemon
      
      # Wait a moment for openvpn to start, then get its PID
      sleep 1
      openvpn_pid=$(pgrep -o -f "openvpn.*$(basename "${temp_config}")")
      if [[ -n "${openvpn_pid}" ]]; then
        echo "${openvpn_pid}" > "${PID_FILE}"
        echo "VPN connection initiated"
        # Cleanup temp config
        [[ -f "${temp_config}" ]] && rm -f "${temp_config}"
      else
        echo "Failed to start VPN"
        [[ -n "${auth_file}" ]] && rm -f "${auth_file}"
        [[ -f "${temp_config}" ]] && rm -f "${temp_config}"
      fi
    fi
    
    break
  else
    echo "Invalid selection."
  fi
done
