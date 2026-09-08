import { test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("./extension/background.js", import.meta.url), "utf8");
const event = () => ({ listeners: [], addListener(fn) { this.listeners.push(fn); }, async emit(...args) { for (const fn of this.listeners) await fn(...args); } });
const settle = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };

async function worker(initialTabs = [], windowList = [{ id: 1, type: "normal" }]) {
    const tabs = initialTabs.map(t => ({ ...t }));
    const posted = [], timers = [], intervals = [], commands = [];
    let serial = 100, stored = {}, failSample = false, running = true, position = 0, project = "";
    const pickerSteps = [];
    const projectPages = [
        [{ id: "1", name: "First" }, { id: "2", name: "Second" }],
        [{ id: "2", name: "Second" }, { id: "3", name: "Third" }]
    ];
    const port = { postMessage: m => posted.push(m), onMessage: event(), onDisconnect: event() };
    const chrome = {
        runtime: { connectNative: () => port, onInstalled: event(), onStartup: event() },
        storage: { session: { get: async () => stored, set: async s => { stored = s; } } },
        scripting: { executeScript: async () => {} },
        tabs: {
            onRemoved: event(), onUpdated: event(),
            query: async () => tabs.filter(t => t.url.startsWith("https://track.toggl.com/")),
            create: async props => { const t = { ...props, id: serial++ }; tabs.push(t); return t; },
            update: async (id, props) => { const t = tabs.find(t => t.id === id); if (!t) throw Error("closed"); Object.assign(t, props); return t; },
            sendMessage: async (id, m) => {
                if (!tabs.some(t => t.id === id) || failSample) throw Error("disconnected");
                if (m.type === "projects") {
                    pickerSteps.push(m.step);
                    if (m.step === "scroll") position = m.position > 0 ? 300 : 0;
                    if (m.step === "select") project = projectPages.flat().find(p => p.id === m.projectId).name;
                    if (m.step === "read") return {
                        projects: projectPages[position > 0 ? 1 : 0], top: position, height: 300, total: 600, loading: false
                    };
                    return { ok: true };
                }
                if (m.type === "command") {
                    commands.push(m);
                    running = m.action === "start";
                    return { ok: true };
                }
                return { available: true, running, project, title: "Test", elapsed: 3 };
            }
        },
        windows: { getAll: async () => windowList, update: async () => {}, onRemoved: event(), onCreated: event() },
        alarms: { create: () => {}, onAlarm: event() },
        action: { onClicked: event() }
    };
    const context = { chrome, URL, console, setInterval: fn => intervals.push(fn),
        setTimeout: (fn, ms) => ms <= 200 ? queueMicrotask(fn) : timers.push(fn) };
    runInNewContext(source, context);
    await settle();
    return { tabs, posted, commands, chrome, port, windowList, intervals, pickerSteps,
        idle: () => { running = false; },
        fail: () => { failSample = true; },
        flush: async () => { while (timers.length) { await timers.shift()(); await settle(); } }
    };
}

test("startup creates one pinned non-discardable background tab", async () => {
    const w = await worker();
    expect(w.tabs).toHaveLength(1);
    expect(w.tabs[0]).toMatchObject({ pinned: true, autoDiscardable: false, active: false });
    await w.chrome.runtime.onStartup.emit();
    await w.chrome.runtime.onInstalled.emit();
    await w.chrome.alarms.onAlarm.emit();
    await settle();
    expect(w.tabs).toHaveLength(1);
    expect(w.posted.some(s => s.available)).toBe(true);
});
test("startup reuses existing timer rather than duplicating it", async () => {
    const w = await worker([{ id: 3, windowId: 1, url: "https://track.toggl.com/timer", pinned: false }]);
    expect(w.tabs).toHaveLength(1);
    expect(w.tabs[0].pinned).toBe(true);
});
test("closing pinned tab restores it, without focusing it", async () => {
    const w = await worker();
    const [removed] = w.tabs.splice(0, 1);
    await w.chrome.tabs.onRemoved.emit(removed.id, { isWindowClosing: false });
    await w.flush();
    expect(w.tabs).toHaveLength(1);
    expect(w.tabs[0].id).not.toBe(removed.id);
    expect(w.tabs[0].active).toBe(false);
});
test("closing all windows does not reopen Helium", async () => {
    const w = await worker();
    const [removed] = w.tabs.splice(0, 1);
    w.windowList.splice(0);
    await w.chrome.tabs.onRemoved.emit(removed.id, { isWindowClosing: true });
    await w.chrome.windows.onRemoved.emit(1);
    await w.flush();
    await w.chrome.alarms.onAlarm.emit();
    await settle();
    expect(w.tabs).toHaveLength(0);
    w.windowList.push({ id: 2, type: "normal" });
    await w.chrome.windows.onCreated.emit();
    await settle();
    expect(w.tabs).toHaveLength(1);
});
test("disconnected tab reports unavailable and native commands reach content", async () => {
    const w = await worker();
    await w.port.onMessage.emit({ id: "x", action: "stop", expectedRunning: true });
    await settle();
    expect(w.commands[0]).toMatchObject({ type: "command", action: "stop", expectedRunning: true });
    expect(w.posted.some(s => s.type === "result" && s.id === "x" && !s.error)).toBe(true);
    w.fail();
    await w.intervals[0]();
    await settle();
    expect(w.posted.at(-1).available).toBe(false);
});

test("project menu scans every virtual page and deduplicates pinned projects", async () => {
    const w = await worker();
    await w.port.onMessage.emit({ id: "projects", action: "projects" });
    const result = w.posted.find(m => m.type === "projects");
    expect(result.projects.map(p => p.id)).toEqual(["1", "2", "3"]);
    expect(w.pickerSteps.at(-1)).toBe("close");
    expect(w.commands).toHaveLength(0);
});

test("start selects the requested project before clicking the timer", async () => {
    const w = await worker();
    w.idle();
    await w.port.onMessage.emit({ id: "start", action: "start", projectId: "3", expectedRunning: false });
    expect(w.pickerSteps).toContain("select");
    expect(w.commands).toHaveLength(1);
    expect(w.commands[0].projectId).toBe("3");
    expect(w.posted.find(m => m.type === "result" && m.id === "start").error).toBe("");
});

test("starting without a project or while running never clicks", async () => {
    const w = await worker();
    await w.port.onMessage.emit({ id: "running", action: "start", projectId: "3" });
    w.idle();
    await w.port.onMessage.emit({ id: "missing", action: "start" });
    expect(w.commands).toHaveLength(0);
    expect(w.posted.filter(m => m.type === "result").every(m => m.error)).toBe(true);
});

test("removed projects report an error and never start an unrelated timer", async () => {
    const w = await worker();
    w.idle();
    await w.port.onMessage.emit({ id: "gone", action: "start", projectId: "99", expectedRunning: false });
    expect(w.commands).toHaveLength(0);
    expect(w.pickerSteps.at(-1)).toBe("close");
    expect(w.posted.find(m => m.type === "result" && m.id === "gone").error).toContain("no longer");
});

test("keeps one pinned Toggl tab and leaves every other tab open", async () => {
    const w = await worker([
        { id: 1, windowId: 1, url: "https://track.toggl.com/timer", pinned: false },
        { id: 2, windowId: 1, url: "https://track.toggl.com/timer", pinned: true },
        { id: 3, windowId: 1, url: "https://track.toggl.com/reports", pinned: true },
        { id: 4, windowId: 1, url: "https://example.com/", pinned: true }
    ]);
    expect(w.tabs).toHaveLength(4);
    expect(w.tabs.find(t => t.id === 2).pinned).toBe(true);
    expect(w.tabs.find(t => t.id === 3).pinned).toBe(false);
    expect(w.tabs.find(t => t.id === 4).pinned).toBe(true);
    const extra = w.tabs.find(t => t.id === 1);
    extra.pinned = true;
    await w.chrome.tabs.onUpdated.emit(extra.id, { pinned: true }, extra);
    await settle();
    expect(extra.pinned).toBe(false);
    expect(w.tabs.filter(t => t.url.startsWith("https://track.toggl.com/") && t.pinned)).toHaveLength(1);
    expect(w.tabs).toHaveLength(4);
});
