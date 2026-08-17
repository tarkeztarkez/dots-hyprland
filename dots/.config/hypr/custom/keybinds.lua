-- Migrated from custom/keybinds.conf
hl.unbind("SUPER + L")
hl.bind("SUPER + L", hl.dsp.exec_cmd("qs -c ii ipc call lock activate"), { description = "Lock" })

hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/lid_close.sh"), { locked = true })
hl.bind("SHIFT + Delete", hl.dsp.global("quickshell:barPeekStart"))
hl.bind("SHIFT + Delete", hl.dsp.global("quickshell:barPeekEnd"), { release = true })

local scripts_dir = "~/.config/hypr/custom/scripts"

local apps = {
	{
		keys = { "CTRL + SUPER + S" },
		name = "Hermes (piggon)",
		process = "/home/tarkeztarkez/.config/hypr/custom/scripts/hermes-piggon.sh",
		class = "Hermes",
		workspace = 11,
	},
	{
		keys = { "SUPER + W" },
		name = "Helium",
		script = "toggle_helium_workspace.sh",
		workspace = 8,
		args = "helium-browser --ozone-platform=x11 --new-window --remote-debugging-port=9222",
	},
	{
		keys = { "SUPER + E" },
		name = "Helium Test",
		script = "toggle_my_browser_workspace.sh",
		workspace = 6,
		args = "helium-browser --ozone-platform=x11 --new-window --remote-debugging-port=9222",
	},
	{ keys = { "SUPER + SHIFT + R" }, name = "Code", process = "zed", class = "dev.zed.Zed", workspace = 10 },
	{ keys = { "SUPER + R" }, name = "Dolphin", process = "dolphin", class = "org.kde.dolphin", workspace = 9 },
		{
			keys = { "SUPER + Return", "SUPER + Escape" },
			name = "Herdr",
			process = "ghostty",
		class = "com.mitchellh.ghostty",
		workspace = 7,
	},
	{ keys = { "SUPER + D" }, name = "Todoist", process = "todoist-wrapper", class = "todoist-wrapper", workspace = 15 },
	{
		keys = { "SUPER + SHIFT + D" },
		name = "Toggl Track",
		script = "toggle_webapp_workspace.sh",
		match = "track\\.toggl\\.com|Toggl Track|Toggl",
		args = "helium-browser --app=https://track.toggl.com/timer --simulate-outdated-no-au",
		title = "Toggl Track",
		workspace = 16,
	},
	{
		keys = { "SUPER + C" },
		script = "toggle_webapp_workspace.sh",
		match = "calendar\\.notion\\.so|Notion Calendar",
		args = "helium-browser --app=https://calendar.notion.so --simulate-outdated-no-au",
		title = "Notion Calendar",
		workspace = 17,
	},
	{
		keys = { "SUPER + G" },
		script = "toggle_webapp_workspace.sh",
		match = "gitea\\.verestro\\.com|Gitea",
		args = "helium-browser --app=https://gitea.verestro.com/ --simulate-outdated-no-au",
		title = "Gitea",
		workspace = 13,
	},
	{
		keys = { "SUPER + Y" },
		script = "toggle_webapp_workspace.sh",
		match = "youtrack\\.verestro\\.com|YouTrack",
		args = "helium-browser --app=https://youtrack.verestro.com/ --simulate-outdated-no-au",
		title = "YouTrack",
		workspace = 14,
	},
	{ keys = { "SUPER + SHIFT + E" }, process = "thunderbird", class = "org.mozilla.Thunderbird", workspace = 18 },
	{ keys = { "SUPER + SHIFT + S" }, name = "Beeper", process = "beeper", class = "BeeperTexts", workspace = 19 },
	{ keys = { "SUPER + S" }, process = "slack", class = "Slack", workspace = 20 },
	{
		keys = { "SUPER + SHIFT + W" },
		name = "ChatGPT",
		script = "toggle_webapp_workspace.sh",
		match = "chatgpt\\.com|ChatGPT",
		args = "helium-browser --app=https://chatgpt.com --simulate-outdated-no-au",
		title = "ChatGPT",
		workspace = 5,
	},
}

local function quote(value)
	return string.format('"%s"', value)
end

local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function app_command(app)
	local script = app.script or "toggle_special.sh"

	if script == "toggle_special.sh" then
		return string.format(
			"%s/%s %s %s %s",
			scripts_dir,
			script,
			quote(app.process),
			quote(app.target or app.class or app.title),
			app.workspace
		)
	end

	if script == "toggle_webapp_workspace.sh" then
		return string.format(
			"%s/%s %s %s %s",
			scripts_dir,
			script,
			app.workspace,
			shell_quote(app.match),
			app.args
		)
	end

	local args = app.args and (" " .. app.args) or ""
	return string.format("%s/%s %s%s", scripts_dir, script, app.workspace, args)
end

local function app_options(app)
	if not app.name then
		return nil
	end

	return { description = "Custom: " .. app.name }
end

for _, app in ipairs(apps) do
	for _, key in ipairs(app.keys) do
		if app.unbind ~= false then
			hl.unbind(key)
		end

		hl.bind(key, hl.dsp.exec_cmd(app_command(app)), app_options(app))
	end
end

hl.unbind("SUPER + B")
hl.unbind("SUPER + Q")
hl.bind("SUPER + Q", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/close_on_double_super_q.sh"), {
	description = "Window: Close on double Super+Q",
})
hl.unbind("SUPER + M")
hl.bind("SUPER + M", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.unbind("SUPER + grave")
hl.bind("SUPER + grave", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/toggle_workspace_group.sh"))
hl.bind("SUPER + SHIFT + grave", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/move_workspace_group.sh"))
hl.bind("CTRL + ALT + V", hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/pasteimage.sh"))
hl.bind("XF86SelectiveScreenshot", hl.dsp.global("quickshell:regionScreenshot"), {
	description = "Utilities: Screen snip",
})
hl.bind(
	"XF86SelectiveScreenshot",
	hl.dsp.exec_cmd(
		"qs -c $qsConfig ipc call TEST_ALIVE || pidof slurp || hyprshot --freeze --clipboard-only --mode region --silent"
	)
)

for _, key in ipairs({
	"code:10",
	"code:11",
	"code:12",
	"code:13",
	"code:14",
	"code:15",
	"code:16",
	"code:17",
	"code:18",
	"code:87",
	"code:88",
	"code:89",
	"code:83",
	"code:84",
	"code:85",
	"code:79",
	"code:80",
	"code:81",
}) do
	hl.unbind("SUPER + " .. key)
	hl.unbind("SUPER + SHIFT + " .. key)
end
for i, key in ipairs({
	"code:10",
	"code:11",
	"code:12",
	"code:13",
	"code:14",
	"code:15",
	"code:16",
	"code:17",
	"code:18",
}) do
	hl.bind("SUPER + SHIFT + " .. key, hl.dsp.focus({ workspace = tostring(i) }))
end
for i, key in ipairs({
	"code:87",
	"code:88",
	"code:89",
	"code:83",
	"code:84",
	"code:85",
	"code:79",
	"code:80",
	"code:81",
}) do
	hl.bind("SUPER + SHIFT + " .. key, hl.dsp.focus({ workspace = tostring(i) }))
end

hl.window_rule({ match = { tag = "helium-test" }, border_color = "rgba(ff5555ff) rgba(ff555588)" })

for _, app in ipairs(apps) do
	if app.workspace and (app.class or app.title) then
		local match = {}

		if app.class then
			match.class = "^(" .. app.class .. ")$"
		end

		if app.title then
			match.title = "^(" .. app.title .. ")$"
		end

		hl.window_rule({ match = match, workspace = app.workspace })
	end
end

-- Helium --app windows can restore their own app-window geometry and map as
-- floating XWayland windows. Force these web apps back into Hyprland tiling.
for _, title in ipairs({
	"ChatGPT",
	"chatgpt\\.com_/",
	"Notion Calendar",
	"calendar\\.notion\\.so_/",
	"Toggl Track",
	"track\\.toggl\\.com_/timer",
	"Gitea",
	"gitea\\.verestro\\.com_/",
	"YouTrack",
	"youtrack\\.verestro\\.com_/",
}) do
	hl.window_rule({ match = { class = "^(Helium)$", title = ".*" .. title .. ".*" }, tile = true })
end

hl.bind(
	"SUPER + F12",
	hl.dsp.exec_cmd('notify-send "Hypr Lua" "Custom keybinds.lua is loaded"'),
	{ description = "Custom: Debug marker" }
)
