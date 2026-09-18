-- Migrated from custom/execs.conf
hl.on("hyprland.start", function()
    hl.exec_cmd("sh -lc 'pkill -x hypridle 2>/dev/null || true; exec hypridle -c ~/.config/hypr/custom/hypridle.conf'")
    hl.exec_cmd("~/.config/hypr/custom/scripts/watch_communications_workspace.sh")
end)
