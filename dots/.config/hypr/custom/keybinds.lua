hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"),
    { description = "Edit user keybinds" })

hl.bind("SHIFT + Delete", hl.dsp.global("quickshell:barPeekStart"), { description = "Temporarily show bar" })
hl.bind("SHIFT + Delete", hl.dsp.global("quickshell:barPeekEnd"), { release = true })
