-- Local workspace routing (Lua)
for i = 1, 10 do
    hl.workspace_rule({ workspace = tostring(i), monitor = "eDP-1", default = (i == 1) })
end
