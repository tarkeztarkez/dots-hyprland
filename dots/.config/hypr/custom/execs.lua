-- Migrated from custom/execs.conf
hl.on("hyprland.start", function()
    hl.exec_cmd("sh -lc 'pkill -x hypridle 2>/dev/null || true; exec hypridle -c ~/.config/hypr/custom/hypridle.conf'")
end)
