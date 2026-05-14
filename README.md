# OpenCode Tray

OpenCode Tray is a small macOS menu bar app for running `opencode serve`.

It starts and stops the server, shows the active URL, generates a phone-friendly QR code, and can launch at login.


<img width="380" height="345" alt="Screenshot 2026-05-14 at 7 32 45 PM" src="https://github.com/user-attachments/assets/a8d824a7-5767-4c7e-9174-91c3755ce48e" />

## Tutorial

Build and open the app:

```bash
sh scripts/build-app.sh
open dist/OpenCodeTray.app
```

Open the tray icon, choose `Settings...`, confirm the defaults, then choose `Start Server`.

## How-To

Run from source:

```bash
swift run OpenCodeTray
```

Use from a phone:

1. Keep Hostname set to `0.0.0.0`.
2. Connect your phone over Tailscale, WireGuard/VPN, or the same LAN.
3. Open `Show Server QR` from the tray menu.

Use password auth:

1. Enable `OpenCode Basic Auth` in Settings.
2. Set Username and Password.
3. Scan the QR URL or use `Copy Server URL`.
4. Enter the username and password manually if the browser prompts.

## Reference

Defaults:

- Executable: `opencode`
- Hostname: `0.0.0.0`
- Port: `4096`
- Working directory: home directory
- mDNS: off, domain `opencode.local`
- OpenCode Basic Auth: off
- Start server when tray opens: on
- Start at Login: off

QR and copied server URLs prefer Tailscale, then WireGuard/VPN-style `utun` private IPs, then LAN private IPs. Passwords are stored in Keychain and are only read after password auth is configured.

The executable resolver checks common GUI-app paths including `~/.opencode/bin`, `~/.bun/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`. Settings also has `Detect` and `Browse...` controls for selecting a specific binary. Node/Bun opencode shims are unwrapped to the native opencode binary when possible.

OpenCode Tray does not embed auth credentials or tokens into shared URLs.

## Explanation

The app runs `opencode serve` as a child process and restarts it when server settings change. Login startup is managed with `~/Library/LaunchAgents/ai.opencode.tray.plist`. The app bundle icon comes from the OpenCode desktop icon, and the tray icon is drawn from the compact OpenCode mark.
