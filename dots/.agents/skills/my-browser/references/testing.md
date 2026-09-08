# Testing and installation

Canonical source is in ~/Projects/dots-hyperland/dots/.agents/skills/my-browser.
The installed ~/.agents/skills/my-browser points to this directory. The existing
~/.local/bin/my-browser symlink resolves scripts/my-browser through that path.
Keep the Hyprland launcher in dots/.config/hypr/custom/scripts in sync with its
installed copy. Run scripts/install.py to register the native host and add the
owned extension path to helium-browser-flags.conf without removing existing flags.
Helium loads it on browser startup. It is already loaded on this machine.
Do not use developerPrivate.loadDirectory for installation. It crashed this
Helium version during setup. The packaged launcher's --load-extension works.

## Local test alternative

These tests run on the desktop host, not Sales Dashboard Docker. The wrapper
requires the host's Hyprland session, existing Helium and loopback CDP endpoint.
Runtime dependencies are Bun, Python 3, hyprctl and the installed agent-browser.
The Python tests use the standard library. No Python package install is needed.

Run from the dots-hyperland repository:

    bun test ./dots/.agents/skills/my-browser/tests/scope.test.ts
    uv run python -m unittest discover -s dots/.agents/skills/my-browser/tests -p 'test_*.py' -v
    uv run --with pyyaml python ~/.agents/skills/skill-creator/scripts/quick_validate.py dots/.agents/skills/my-browser

The live test requires explicit opt-in because it uses the user's browser:

    MY_BROWSER_LIVE_TEST=1 uv run python -m unittest discover -s dots/.agents/skills/my-browser/tests -p test_live.py -v

It creates two new native groups in Super+E and uses only synthetic about:blank
tabs. It tests parallel clicks with independent refs, moving a test tab into the
other test group, refusal while moved, recovery after restoring it, a busy-session
lock and externally closing the selected tab. It closes its own tabs in finally.
It does not navigate to real services or modify existing tabs.

## State and recovery

Private state and lock files live in $XDG_RUNTIME_DIR/my-browser/sessions.
Without XDG_RUNTIME_DIR, the wrapper uses /run/user/UID. State files are mode 0600
and atomic replacements use .pending files. Each group has a random session suffix.
Local proxy endpoints are private control addresses. Do not publish state files.

finish closes owned tabs, their automation daemons and proxy processes.
Idle automation daemons disconnect after five minutes. Take a fresh snapshot if
the daemon restarted; the proxy still exposes only the same owned target.
A closed or restarted browser
does not authorize adopting new tabs. Keep failed session state for diagnosis.
Do not delete the old shared binding.json to redirect another running agent.

The wrapper uses compact hashes for daemon socket names, because Unix socket
paths have a small length limit. The full task name remains in the browser group.

## Acceptance evidence

The live regression test passed on the existing Super+E Helium. Both groups had
different native group IDs in the same native window. Each page retained its own
three-click counter. Moving a tab blocked the write, restoring it allowed reads,
and closing it did not redirect the next command to the other group.

This verifies browser steering and grouping. It is not evidence that the Sales
Dashboard vault, physical passkeys or cross-origin PRF passed browser acceptance.

The same live regression passed with the owned My Browser extension and native
host. Pairing tests cover changed titles, ambiguity, browser restart and message
size limits. The launcher closes its lock descriptor in both browser launch paths,
so Helium cannot retain the startup lock. New bootstrap URLs contain random UUIDs.

Installation incident: Helium exited with SIGSEGV while loading a DirectoryEntry
through developerPrivate.loadDirectory. The normal launchers recreated Super+W
and tagged Super+E. Previous tabs were not confirmed restored. No browser profile
or session files were edited. This incident is not a successful restore test.
