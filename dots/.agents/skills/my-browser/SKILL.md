---
name: my-browser
description: Use the user's Super+E Helium browser with a separate task-owned tab group and scoped automation session. Trigger for my browser, my profile, Helium, or browser work that must not touch Super+W.
allowed-tools: Bash(my-browser:*)
---

# My browser

Use only my-browser. Never call agent-browser directly or connect another tool
to port 9222. The wrapper identifies the tagged Super+E window on workspace 6.
It refuses ambiguous windows rather than guessing from the newest tab.

## Start once per task

Run my-browser start TASK, where TASK is a short lowercase name such as vault-qa.
The JSON result contains a unique session ID, group ID and target ID.
Reuse that exact session ID for this task. Every agent starts its own session,
even if several agents work on the same project.

Commands:

    my-browser start vault-qa
    my-browser --session RETURNED_ID open https://sales-dashboard.verestro.dev.local:3443/vault-keys
    my-browser --session RETURNED_ID snapshot -i
    my-browser --session RETURNED_ID click @e1
    my-browser --session RETURNED_ID fill @e2 "test input"
    my-browser --session RETURNED_ID screenshot /tmp/vault-page.png

The group is named AI followed by the unique session ID. Tabs open in the
background. Commands do not activate the browser tab or steal desktop focus.
Refs belong to the selected tab's automation session. Snapshot again after
navigation or DOM changes. Never reuse another session's refs.

If native clicks or keyboard input do not work in a background tab, run
my-browser --session RETURNED_ID activate. This visually selects only the owned
tab inside Super+E. It does not focus another desktop window. Snapshot again
before interacting. Use focus followed by press Enter when an extension popup
interferes with a button's click coordinates.

## More tabs and cleanup

    my-browser --session RETURNED_ID new-tab https://example.com
    my-browser --session RETURNED_ID tabs
    my-browser --session RETURNED_ID select OWNED_TARGET_ID
    my-browser --session RETURNED_ID close-tab OWNED_TARGET_ID
    my-browser --session RETURNED_ID status
    my-browser --session RETURNED_ID finish

new-tab selects the new tab for automation, without visually activating it.
tabs lists only tabs created by this session. select accepts the native target
ID returned by new-tab or tabs, not t1 or an index from another tool.

finish closes only the tabs the session created. It leaves manually added tabs
alone. It never closes Helium or another agent's group. Do not finish a session
while waiting for the user to approve something in its tab.

## Failure rules

- A session ID is mandatory. There is no shared default or reset-binding fallback.
- Commands with the same session ID cannot run concurrently. A busy error means
  wait for that operation to end. Different sessions can run in parallel.
- Moving an owned tab out of its group or window stops commands. Restore its
  placement or start a new session. Do not adopt an unrelated tab.
- Closing the selected tab does not select another automatically. Explicitly
  select a remaining owned tab, or finish and start again.
- A browser restart invalidates old sessions. Do not reuse their target IDs.
- Connection/profile overrides, raw tab/session controls, browser close,
  recording and browser-launch commands are refused. Do not bypass this guard.
- Uncertain writes are not retried automatically. Inspect the result first.

## How grouping works

Each task has private state and a lock. Each owned tab has a separate automation
daemon and a local CDP proxy that exposes that tab and its child frame sessions.
Unrelated pages and their console events are not forwarded. Browser-wide closing,
new-target creation and focus activation through this connection are blocked.
Ownership is checked before and after each command.

Native tab grouping uses the owned My Browser extension, never another installed
extension. Its native host pairs the tagged Hyprland window with the browser's
window ID. New windows have a unique local bootstrap URL for automatic pairing.
The pairing persists through title changes and expires on browser/window restart.
The launcher opens Super+E when missing and never passes its bootstrap to Super+W.
No user selection or confirmation is required for normal operation. Ambiguous
initial pairing fails without opening a tab in an unconfirmed window.

The extension has tabs, tabGroups and nativeMessaging permissions. It has no
content scripts or website host permissions. The native host reads window
metadata and accepts no shell commands. Group operations use only this extension.

Groups are not separate browser profiles. Cookies, logins and storage are shared.
This prevents accidental cross-task steering, not hostile JavaScript or a user
manually navigating the owned tab. Use isolated local hosts for development tests.
Site-created popup windows are not automatically adopted. Use new-tab explicitly.

## Maintenance

my-browser guide prints the version-matched browser command reference.
See references/testing.md for unit tests, live regression tests and deployment.
