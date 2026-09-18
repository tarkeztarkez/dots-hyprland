-- Migrated from custom/rules.conf
hl.config({
    input = {
        kb_options = "compose:rctrl, caps:swapescape",
    },
})

-- Prevent Helium windows controlled through CDP/agent-browser from activating/focusing themselves.
hl.window_rule({ match = { class = "^(Helium)$" }, suppress_event = "activate activatefocus" })

-- Keep Slack's auxiliary huddle window out of the Slack/Thunderbird split.
hl.window_rule({
    match = { class = "^(Slack)$", initial_title = "^(Slack - Huddle Preview)$" },
    float = true,
})
