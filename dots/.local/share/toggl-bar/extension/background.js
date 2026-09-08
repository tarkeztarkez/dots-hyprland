const URL = "https://track.toggl.com/timer";
const HOST = "local.toggl_bar";
let port;
let tabId;
let ensuring;
let sampling = false;
let projectCache = [];

const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

async function picker(step, extra = {}) {
    const result = await chrome.tabs.sendMessage(tabId, { type: "projects", step, ...extra });
    if (result.error) throw new Error(result.error);
    return result;
}

async function scanProjects(selectId) {
    await picker("open");
    const found = new Map();
    let bottomWaits = 0;
    let stableBottom = 0;
    let lastBottom = "";
    try {
        await pause(150);
        await picker("scroll", { position: 0 });
        for (let step = 0; step < 100; step++) {
            await pause(100);
            const view = await picker("read");
            if (view.top === undefined) continue;
            for (const project of view.projects) found.set(project.id, project);
            if (selectId && view.projects.some(project => project.id === selectId)) {
                await picker("select", { projectId: selectId });
                return view.projects.find(project => project.id === selectId);
            }
            if (view.top + view.height >= view.total - 1) {
                const signature = JSON.stringify([view.total, [...found.keys()]]);
                stableBottom = signature === lastBottom ? stableBottom + 1 : 0;
                lastBottom = signature;
                if (stableBottom < 5) continue;
                if (view.loading && bottomWaits++ < 10) continue;
                if (selectId) throw new Error("Project is no longer available");
                projectCache = [...found.values()].sort((a, b) => a.name.localeCompare(b.name));
                post({ type: "projects", projects: projectCache });
                if (view.loading) throw new Error("Toggl is still loading some projects. Showing the projects it has loaded.");
                return;
            }
            await picker("scroll", { position: view.top + Math.max(36, view.height - 36) });
        }
        throw new Error("Could not read all projects. Try again.");
    } finally {
        await picker("close").catch(() => {});
    }
}

async function ensureTab() {
    if (ensuring) return ensuring;
    ensuring = (async () => {
        const windows = (await chrome.windows.getAll()).filter(w => w.type === "normal" && !w.incognito);
        if (!windows.length) return null; // Do not reopen Helium during shutdown.
        const saved = await chrome.storage.session.get(["tabId", "windowId"]);
        const tabs = await chrome.tabs.query({ url: "https://track.toggl.com/*" });
        let tab = tabs.find(t => t.id === (tabId ?? saved.tabId) && new globalThis.URL(t.url).pathname === "/timer")
            || tabs.find(t => t.pinned && new globalThis.URL(t.url).pathname === "/timer" && !t.incognito)
            || tabs.find(t => new globalThis.URL(t.url).pathname === "/timer" && !t.incognito);
        const targetWindow = windows.find(w => w.id === saved.windowId) || windows.find(w => w.focused) || windows[0];
        if (!tab) tab = await chrome.tabs.create({ url: URL, pinned: true, active: false, windowId: targetWindow.id });
        tabId = tab.id;
        await chrome.storage.session.set({ tabId, windowId: tab.windowId });
        await chrome.tabs.update(tabId, { pinned: true, autoDiscardable: false });
        await Promise.all(tabs.filter(t => t.id !== tabId && t.pinned)
            .map(t => chrome.tabs.update(t.id, { pinned: false }).catch(() => {})));
        const verified = await chrome.tabs.query({ url: "https://track.toggl.com/*" });
        post({ type: "tabs", tabs: verified.map(t => ({ id: t.id, pinned: t.pinned === true, managed: t.id === tabId })) });
        return tabId;
    })();
    try { return await ensuring; } finally { ensuring = null; }
}

function post(message) {
    try { port?.postMessage(message); } catch { port = null; }
}

async function sample() {
    if (sampling) return;
    sampling = true;
    try {
        if (!port) connect();
        if (!tabId) await ensureTab();
        const state = await chrome.tabs.sendMessage(tabId, { type: "sample" });
        post({ type: "state", ...state });
    } catch (error) {
        post({ type: "state", available: false, reason: "Toggl tab: " + error.message });
    } finally { sampling = false; }
}

async function command(message) {
    try {
        if (message.action === "open") {
            await ensureTab();
            const tab = await chrome.tabs.update(tabId, { active: true });
            await chrome.windows.update(tab.windowId, { focused: true });
        } else if (message.action === "projects") {
            await scanProjects();
        } else {
            if (message.action === "start") {
                const before = await chrome.tabs.sendMessage(tabId, { type: "sample" });
                if (!before.available || before.running) throw new Error("Timer changed. Try again.");
                if (!message.projectId) throw new Error("Choose a project first");
                const selected = await scanProjects(message.projectId);
                let ready = false;
                for (let attempt = 0; attempt < 10; attempt++) {
                    const state = await chrome.tabs.sendMessage(tabId, { type: "sample" });
                    if (!state.available || state.running) throw new Error("Timer changed. Try again.");
                    if (state.project === selected.name) { ready = true; break; }
                    await pause(100);
                }
                if (!ready) throw new Error("Toggl did not select the project. Try again.");
            }
            const result = await chrome.tabs.sendMessage(tabId, { type: "command", ...message });
            if (result.error) throw new Error(result.error);
            let confirmed = false;
            for (let attempt = 0; attempt < 20; attempt++) {
                const state = await chrome.tabs.sendMessage(tabId, { type: "sample" });
                post({ type: "state", ...state });
                if (state.available && state.running === (message.action === "start")) {
                    confirmed = true;
                    break;
                }
                await new Promise(resolve => setTimeout(resolve, 200));
            }
            if (!confirmed) throw new Error("Toggl did not change the timer. Check the page.");
        }
        post({ type: "result", id: message.id, error: "" });
        await sample();
    } catch (error) {
        post({ type: "result", id: message.id, error: error.message });
    }
}

function connect() {
    if (port) return;
    try {
        port = chrome.runtime.connectNative(HOST);
        port.onMessage.addListener(command);
        port.onDisconnect.addListener(() => {
            console.warn("Toggl bridge disconnected", chrome.runtime.lastError?.message || "");
            port = null;
        });
    } catch (error) { console.warn(error); }
}

async function boot() {
    connect();
    const id = await ensureTab();
    if (id) {
        // Declarative content scripts do not attach to tabs open before installation.
        try { await chrome.scripting.executeScript({ target: { tabId: id }, files: ["page.js"] }); }
        catch (error) {
            post({ type: "state", available: false, reason: "Toggl attachment failed: " + error.message });
            return;
        }
    }
    await sample();
}
chrome.runtime.onInstalled.addListener(() => void boot());
chrome.runtime.onStartup.addListener(() => void boot());
chrome.action.onClicked.addListener(() => void command({ action: "open" }));
chrome.tabs.onRemoved.addListener((id, info) => {
    if (id !== tabId) return;
    tabId = null;
    post({ type: "state", available: false, reason: "Reopening Toggl" });
    // Closing a window must not spawn a replacement window.
    if (!info.isWindowClosing) setTimeout(() => void ensureTab().catch(console.warn), 500);
});
chrome.windows.onRemoved.addListener(() => {
    setTimeout(() => void ensureTab().catch(console.warn), 1000);
});
chrome.windows.onCreated.addListener(() => void ensureTab().catch(console.warn));
chrome.tabs.onUpdated.addListener((id, change, tab) => {
    const toggl = (tab?.url || change.url || "").startsWith("https://track.toggl.com/");
    if ((id === tabId && (change.pinned === false || change.url))
        || (toggl && (change.pinned === true || (tab?.pinned && change.url))))
        void ensureTab().catch(console.warn);
});
chrome.alarms.create("recover", { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(() => void boot().catch(console.warn));
// A connected native port keeps this service worker alive. Polling in the worker
// avoids background-tab timer throttling. No network requests are made here.
setInterval(() => void sample(), 2000);
void boot().catch(console.warn);
