# Vigil 🕯️

A macOS menu bar app that keeps your Mac awake — even with the lid closed — so long-running work can continue overnight.

- **Keep Awake**: toggles `sudo pmset -a disablesleep 1/0`, which prevents all system sleep including lid-close sleep
- **Auto-off timer**: pick a duration (15 min – 12 hours, or indefinitely) and Vigil re-enables sleep automatically when it expires — no more forgetting to turn `disablesleep` back off. The deadline is persisted, so it survives an app restart
- **Lock & screen off on lid close**: with `disablesleep` on, macOS keeps the display alive and
  unlocked even when the lid is closed. Vigil watches the clamshell state (event-driven via IOKit,
  no polling) and locks the session + sleeps the display the moment the lid closes, while
  processes keep running. Can be turned off in the menu
- The menu bar icon (a candle) turns orange while active
- **Launch at login** can be toggled from the menu
- `caffeinate` processes running on the system are detected when the menu opens and shown with their parent process name and estimated remaining time (display only)

## Build & Install

```sh
make install   # install to /Applications/Vigil.app
make run       # build a bundle into dist/ and launch it
```

## Passwordless toggling

Toggling `pmset disablesleep` requires admin privileges, so by default an authentication dialog
appears on every toggle. Clicking "Allow toggling without password…" in the menu installs a
sudoers rule scoped to `pmset -a disablesleep` only, at `/etc/sudoers.d/vigil` (authentication
required once). After that, toggling — including the automatic off when the timer expires — is
instant and passwordless.

## Syncing with changes made outside the app

`disablesleep` is re-read from `pmset -g` every time the menu opens, so manual `sudo pmset`
changes are reflected in the toggle. If sleep was re-enabled manually, any pending auto-off
timer is cancelled.

## Notes

- Quitting the app always re-enables sleep (`pmset disablesleep 0`). If the app dies without a
  chance to clean up (crash, force quit), the persisted auto-off deadline is handled on the next
  launch instead: an expired deadline re-enables sleep silently (requires the sudoers rule), a
  pending one resumes counting down
- Why not `caffeinate`? For keeping the machine running, `disablesleep` is a superset: it covers
  idle sleep and lid-close sleep, works on battery, and unlike `caffeinate -s` doesn't stop at
  AC power. What `caffeinate` had over it — a self-expiring timeout — is what the auto-off timer
  provides
