# Toggl bar

Replaces the horizontal Quickshell media widget with Toggl Track.

## Controls

- Hover while idle to open the project menu. Click a project to start its timer.
- Click the running timer to stop it.
- Right-click to focus Toggl in Helium.
- Start and stop update the widget immediately. The icon dims until Toggl confirms the change. Failed or timed-out actions roll back and show an error.
- When Helium or the tab disconnects, the widget shows "Unavailable". Stale heartbeats expire after 12 seconds.

Projects come from the timer page's project picker in the current workspace. The extension scrolls the virtualized list and deduplicates pinned entries. The widget caches the list for five minutes. If Toggl is still loading projects, the menu shows the entries it found and a warning rather than claiming the list is complete.

Selecting a project uses Toggl's current description draft. It does not resume an old entry or create a project.

## What runs locally

The extension reads the page's DOM and clicks its controls. It makes no direct Toggl API requests, reads no API token, and does not inspect cookies or internal application stores. Toggl's website still syncs with Toggl normally.

Helium launches `bridge.py` through native messaging. Quickshell reads status and sends commands through `$XDG_RUNTIME_DIR/toggl-bar/bridge.sock`. Its directory has mode 0700 and the socket has mode 0600. Timer and project data stay in memory. No local HTTP server or separate background service is needed.

The extension keeps exactly one Toggl tab pinned and sets `autoDiscardable: false` on its timer tab. Other Toggl tabs may stay open, but the extension unpins them if they become pinned. It never closes those extra tabs or changes pins on other websites.

Closing the managed tab recreates it in its previous window when that window still exists. Startup reuses an existing timer tab when available. Closing every normal window does not reopen Helium. Disable the extension if you want to close the timer tab permanently.

## Install

From the repository root:

```sh
uv run --no-project python dots/.local/share/toggl-bar/install.py
```

In Helium, open `chrome://extensions`, enable Developer mode, choose Load unpacked, and select `~/.local/share/toggl-bar/extension`. Keep that directory in place. The installer registers the native host under `~/.config/net.imput.helium/NativeMessagingHosts`. Its allowed extension ID derives from the installed directory path.

The Quickshell files are:

- `dots/.config/quickshell/ii/modules/ii/bar/BarContent.qml`
- `dots/.config/quickshell/ii/modules/ii/bar/TogglWidget.qml`
- `dots/.config/quickshell/ii/services/TogglTrack.qml`
- `dots/.config/quickshell/ii/services/TogglOptimistic.js`

Deploy those through the dotfiles setup, or copy the changed files to their corresponding paths under `~/.config/quickshell/ii`. Compare existing local changes before replacing `BarContent.qml`.

Restart Quickshell after deployment. On this machine, hot reload lost themed workspace icons until a full restart. The project popup uses a Loader so it cannot create an anchor before the bar has a window.

After updating the extension or bridge, rerun the installer and click Reload for Toggl bar in Helium.

## Tests

From the repository root:

```sh
bun test ./dots/.local/share/toggl-bar/*.test.js
uv run --no-project python -m unittest discover -s dots/.local/share/toggl-bar -p 'test_*.py' -v
```

The tests cover tab startup and recovery, shutdown without reopening windows, DOM selectors, virtualized projects, project selection before start, stale commands, native message framing, socket permissions, disconnects, and optimistic confirmation or rollback.

The standalone `dots/.config/quickshell/ii/toggl-widget-test.qml` uses a fake tracker. It never sends commands to Helium. Copy it next to the live `shell.qml` and run:

```sh
quickshell -p ~/.config/quickshell/ii/toggl-widget-test.qml
quickshell ipc -p ~/.config/quickshell/ii/toggl-widget-test.qml call togglWidgetTest menu
quickshell ipc -p ~/.config/quickshell/ii/toggl-widget-test.qml call togglWidgetTest start 1
quickshell ipc -p ~/.config/quickshell/ii/toggl-widget-test.qml call togglWidgetTest status
```

Other fixture commands are `stop`, `idle`, and `unavailable`.

Live checks performed on this machine:

- Loaded the unpacked extension and confirmed that the native host connected.
- Read the running timer and the four projects from the real Toggl page.
- Closed the managed tab and observed its replacement reconnect.
- Disabled the extension and verified "Unavailable" in the bar. Re-enabling restored the timer without adding a duplicate tab.
- Rendered the project menu and tested selection, stop, and unavailable controls in the isolated QML fixture.
- Restarted Quickshell and verified that workspace icons remained visible.

Browser startup and full shutdown use automated mocks. The checks did not quit the user's Helium windows or deliberately change a live time entry.

## Troubleshooting

```sh
python3 ~/.local/share/toggl-bar/bridge.py status
```

If unavailable, check that Toggl bar is enabled, its native host manifest points to the installed bridge, and the timer tab is signed in. Only timer mode and the page's h:mm:ss duration format are supported. Changed page markup fails closed instead of guessing which control to click.

No command is replayed after a disconnect. A confirmation means the page changed its timer state, not that Toggl's server saved it. Check the page if its own sync is failing.
