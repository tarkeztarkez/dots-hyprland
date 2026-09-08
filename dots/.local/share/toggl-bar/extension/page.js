// Read only the visible timer controls. Never inspect cookies or app stores.
(() => {
    // Chromium may retain the isolated world's globals after an extension reload.
    // Replace the listener instead of treating an old boolean as a live connection.
    if (globalThis.__togglBarListener)
        chrome.runtime.onMessage.removeListener(globalThis.__togglBarListener);
    const buttonSelector = '[data-dom-element-id="timer-button"]';
    const pickerSelector = '[aria-label="Add a project"]';
    const pickerState = globalThis.__togglBarPickerState ||= { opened: false };

    function projects(message) {
        const picker = document.querySelector(pickerSelector);
        if (!picker) return { error: "Toggl's project picker is unavailable" };
        let grid = picker.querySelector('[class*="ProjectsContainer"] [role="grid"]');
        if (message.step === "open") {
            if (!grid) {
                picker.querySelector('[tabindex="0"]').click();
                pickerState.opened = true;
            }
            return { ok: true };
        }
        if (message.step === "close") {
            if (pickerState.opened) picker.querySelector('[class*="Overlay-overlayStyles"]')?.click();
            pickerState.opened = false;
            return { ok: true };
        }
        if (!grid) return { loading: true, projects: [] };
        if (picker.querySelector('input')?.value)
            return { error: "Clear the search in Toggl's project picker first" };
        if (message.step === "scroll") {
            grid.scrollTop = message.position;
            return { ok: true };
        }
        if (message.step === "select") {
            if (read().running || !read().available) return { error: "Timer changed. Try again." };
            if (!/^\d+$/.test(message.projectId)) return { error: "Invalid project" };
            const row = grid.querySelector('[data-tracking-id="select-project-' + message.projectId + '"]');
            if (!row) return { error: "Project is no longer available" };
            row.querySelector('[class*="ProjectName"]').click();
            pickerState.opened = false;
            return { ok: true };
        }
        const rows = [...grid.querySelectorAll('[data-tracking-id^="select-project-"]')];
        return {
            projects: rows.map(row => ({
                id: row.getAttribute("data-tracking-id").replace("select-project-", ""),
                name: row.querySelector('[class*="ProjectName"]')?.textContent.trim() || "",
                client: row.querySelector('[class*="ClientName"]')?.textContent.trim() || "",
                color: row.querySelector('[class*="ProjectName"]')?.getAttribute("color") || ""
            })).filter(project => /^\d+$/.test(project.id) && project.name),
            top: grid.scrollTop, height: grid.clientHeight, total: grid.scrollHeight,
            loading: grid.textContent.includes("Loading...")
        };
    }
    function read() {
        const button = document.querySelector(buttonSelector);
        const mode = button?.getAttribute("data-tracking-id");
        const running = mode === "stop-te-timer-mode";
        const idle = mode === "start-te-timer-mode";
        const duration = document.querySelector('[aria-label="Time entry duration"]');
        const match = duration?.textContent.trim().match(/^(\d+):(\d{2}):(\d{2})$/);
        if (!button || button.disabled || (!running && !idle) || !match)
            return { available: false, reason: "Open Toggl's timer view and sign in" };
        const description = document.querySelector('[aria-label="Time entry description"] [data-placeholder]')?.textContent.trim() || "";
        const project = document.querySelector('[aria-label="Add a project"] [class*="ProjectName"]')?.textContent.trim() || "";
        return {
            available: navigator.onLine, running,
            project,
            title: (description || project || "No description").slice(0, 240),
            elapsed: Number(match[1]) * 3600 + Number(match[2]) * 60 + Number(match[3]),
            reason: navigator.onLine ? "" : "Browser is offline"
        };
    }
    const listener = (message, sender, respond) => {
        if (sender.id !== chrome.runtime.id) return;
        if (message.type === "sample") respond(read());
        if (message.type === "projects") {
            try { respond(projects(message)); }
            catch (error) { respond({ error: error.message }); }
        }
        if (message.type === "command") {
            const state = read();
            // Explicit start/stop, never toggle. A retry cannot reverse the action.
            if (!state.available) return respond({ error: state.reason });
            if (!["start", "stop"].includes(message.action)) return respond({ error: "Unknown action" });
            if (state.running !== message.expectedRunning)
                return respond({ error: "Timer changed. Try again." });
            if (state.running !== (message.action === "start"))
                document.querySelector(buttonSelector).click();
            respond({ ok: true });
        }
    };
    globalThis.__togglBarListener = listener;
    chrome.runtime.onMessage.addListener(listener);
})();
