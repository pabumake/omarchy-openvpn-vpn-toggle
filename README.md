# OpenVPN Toggle for Omarchy Waybar

OpenVPN toggle module for Omarchy Waybar, with install and uninstall automation.

This repository adds a `custom/vpn` module to Waybar that:
- Left-clicks to connect or disconnect OpenVPN
- Right-clicks to choose a profile and set credentials
- Shows connected/disconnected/not-configured state through Waybar JSON

Based on the setup shared in [Omarchy Discussion #1366](https://github.com/basecamp/omarchy/discussions/1366).

## Requirements

- Omarchy / Waybar environment
- `bash`
- `openvpn`
- `waybar`
- `jq`
- One or more `.ovpn` files in `~/.config/openvpn`

Arch install example:

```bash
sudo pacman -S openvpn waybar jq
```

## Installation

One-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/pabumake/omarchy-openvpn-vpn-toggle/main/install.sh | bash
```

Or local clone:

```bash
git clone https://github.com/pabumake/omarchy-openvpn-vpn-toggle.git
cd omarchy-openvpn-vpn-toggle
./install.sh
```

The installer:
- Validates dependencies (`openvpn`, `waybar`, `jq`)
- Checks `~/.config/openvpn` for `.ovpn` files (offers to continue if none found)
- Installs scripts to `~/.config/waybar/scripts`
- Creates `vpn.conf` if missing
- Updates Waybar config (`config.jsonc` or `config`) to add `custom/vpn`
- Updates `style.css` to include `#custom-vpn` with `#custom-omarchy`
- Optionally adds UFW `tun+` rules if UFW is active
- Optionally adds `/etc/sudoers.d/openvpn-vpn-toggle`
- Offers to restart Waybar

Do not run `install.sh` as root; it prompts for `sudo` only when needed.

## Usage

- Left-click the VPN icon: toggle connect/disconnect (`vpn-toggle.sh`)
- Right-click the VPN icon: select profile and credentials (`vpn-select.sh`)
- Status refresh runs every 3 seconds (`vpn-status.sh`)

Manual commands:

```bash
~/.config/waybar/scripts/vpn-status.sh
~/.config/waybar/scripts/vpn-toggle.sh
~/.config/waybar/scripts/vpn-select.sh
```

## OpenVPN Profiles and Credentials

Profile discovery path:

```bash
~/.config/openvpn/*.ovpn
```

Credential flow used by `vpn-select.sh`:
- Reads optional inline values from the selected `.ovpn`:
  - `# VPN_USER=...` or `; VPN_USER=...`
  - `# VPN_PASSWORD=...` or `; VPN_PASSWORD=...`
- If not present, prompts interactively
- Stores profile credentials in:
  - `~/.config/waybar/scripts/.creds/<profile>.creds`
- Writes current selection to:
  - `~/.config/waybar/scripts/vpn.conf`

`vpn-toggle.sh` creates temporary auth files (`.vpn_auth_*`) and a temporary sanitized config (`.vpn_config_sanitized_*.ovpn`) in the scripts directory, then cleans them up.

## Waybar Module Added by Installer

`install.sh` adds this module key:

- `custom/vpn`

With behavior:
- `exec`: `$HOME/.config/waybar/scripts/vpn-status.sh`
- `on-click`: `$HOME/.config/waybar/scripts/vpn-toggle.sh`
- `on-click-right`: `omarchy-launch-floating-terminal-with-presentation $HOME/.config/waybar/scripts/vpn-select.sh`
- `interval`: `3`
- `return-type`: `json`
- `signal`: `8`
- `format-icons`: `none`, `connected`, `disconnected`

## Uninstall

Run:

```bash
./install.sh --uninstall
```

Uninstall removes:
- `~/.config/waybar/scripts/vpn-status.sh`
- `~/.config/waybar/scripts/vpn-toggle.sh`
- `~/.config/waybar/scripts/vpn-select.sh`
- `~/.config/waybar/scripts/vpn.conf`
- `custom/vpn` from Waybar config
- `#custom-vpn` styling entry
- `/etc/sudoers.d/openvpn-vpn-toggle` (if present)

It also creates timestamped backups before editing Waybar config and styles.
It does not remove `~/.config/waybar/scripts/.creds`, `~/.config/waybar/scripts/vpn.pid`, `~/.config/waybar/scripts/vpn.log`, or backup files.

## Troubleshooting

No profiles found:

```bash
ls -lh ~/.config/openvpn
```

Check script install:

```bash
ls -lh ~/.config/waybar/scripts/vpn-*.sh
```

Validate JSON config:

```bash
jq . ~/.config/waybar/config.jsonc
# or:
jq . ~/.config/waybar/config
```

OpenVPN connect issues:
- Primary log file: `~/.config/waybar/scripts/vpn.log`
- Manual test:

```bash
sudo openvpn --config ~/.config/openvpn/<your-profile>.ovpn
```

If toggling prompts for password every time:
- Re-run installer and allow sudoers setup, or
- Add the rule manually with `visudo`:

```text
%wheel ALL=(ALL) NOPASSWD: /usr/bin/openvpn, /usr/bin/kill, /usr/bin/expect
# or, on systems using sudo group:
%sudo ALL=(ALL) NOPASSWD: /usr/bin/openvpn, /usr/bin/kill, /usr/bin/expect
```

## Development

Syntax check:

```bash
bash -n install.sh
for script in scripts/*.sh; do bash -n "$script"; done
```

## License

MIT. See `LICENSE`.
