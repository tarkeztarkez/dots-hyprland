-- Migrated from custom/rules.conf
hl.config({
    input = {
        kb_options = "compose:rctrl, caps:swapescape",
    },
})

-- Prevent Helium windows controlled through CDP/agent-browser from activating/focusing themselves.
hl.window_rule({ match = { class = "^(Helium)$" }, suppress_event = "activate activatefocus" })

-- Float Slack's auxiliary huddle window instead of tiling it next to Slack.
hl.window_rule({
    match = { class = "^(Slack)$", initial_title = "^(Slack - Huddle Preview)$" },
    float = true,
})
