import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("./extension/page.js", import.meta.url), "utf8");

function page(mode = "stop-te-timer-mode", duration = "1:02:03") {
    let listener;
    let clicks = 0;
    const button = { disabled: false, getAttribute: () => mode, click: () => { clicks++; } };
    const elements = {
        '[data-dom-element-id="timer-button"]': button,
        '[aria-label="Time entry duration"]': { textContent: duration },
        '[aria-label="Time entry description"] [data-placeholder]': { textContent: "Build <widget>" },
        '[aria-label="Add a project"] [class*="ProjectName"]': { textContent: "Work" }
    };
    const context = {
        document: { querySelector: key => elements[key] || null },
        navigator: { onLine: true },
        chrome: { runtime: { id: "test", onMessage: { addListener: fn => { listener = fn; } } } }
    };
    runInNewContext(source, context);
    return {
        context, elements, button,
        clicks: () => clicks,
        send: (message, id = "test") => {
            let result;
            listener(message, { id }, value => { result = value; });
            return result;
        }
    };
}

describe("Toggl page controls", () => {
    test("reads duration and title without HTML interpretation", () => {
        const p = page();
        expect(p.send({ type: "sample" })).toMatchObject({ available: true, running: true, elapsed: 3723, title: "Build <widget>" });
    });
    test("idle and empty description use project", () => {
        const p = page("start-te-timer-mode", "0:00:00");
        p.elements['[aria-label="Time entry description"] [data-placeholder]'].textContent = "";
        expect(p.send({ type: "sample" })).toMatchObject({ available: true, running: false, title: "Work" });
    });
    test("missing, changed, disabled or manual controls fail closed", () => {
        for (const mode of ["unknown", "start-te-manual-mode"]) {
            expect(page(mode).send({ type: "sample" }).available).toBe(false);
        }
        const p = page();
        p.button.disabled = true;
        expect(p.send({ type: "sample" }).available).toBe(false);
        expect(page("stop-te-timer-mode", "1.5 h").send({ type: "sample" }).available).toBe(false);
        delete p.elements['[data-dom-element-id="timer-button"]'];
        expect(p.send({ type: "sample" }).available).toBe(false);
    });
    test("offline cannot control the timer", () => {
        const p = page();
        p.context.navigator.onLine = false;
        expect(p.send({ type: "command", action: "stop", expectedRunning: true }).error).toBeTruthy();
        expect(p.clicks()).toBe(0);
    });
    test("start and stop use exactly one click", () => {
        for (const [mode, action, expectedRunning] of [
            ["stop-te-timer-mode", "stop", true],
            ["start-te-timer-mode", "start", false]
        ]) {
            const p = page(mode);
            expect(p.send({ type: "command", action, expectedRunning }).ok).toBe(true);
            expect(p.clicks()).toBe(1);
        }
    });
    test("stale state, other extensions and invalid commands cannot click", () => {
        const p = page();
        expect(p.send({ type: "command", action: "start", expectedRunning: false }).error).toBeTruthy();
        expect(p.send({ type: "command", action: "delete", expectedRunning: true }).error).toBeTruthy();
        expect(p.send({ type: "command", action: "stop", expectedRunning: true }, "other")).toBeUndefined();
        expect(p.clicks()).toBe(0);
    });
    test("reinjection replaces a stale listener without duplicating it", () => {
        const p = page();
        let removed = 0, added = 0;
        const register = p.context.chrome.runtime.onMessage.addListener;
        p.context.chrome.runtime.onMessage.removeListener = () => { removed++; };
        p.context.chrome.runtime.onMessage.addListener = fn => { added++; register(fn); };
        runInNewContext(source, p.context);
        expect(removed).toBe(1);
        expect(added).toBe(1);
        p.send({ type: "command", action: "stop", expectedRunning: true });
        expect(p.clicks()).toBe(1);
    });
});

function projectPicker() {
    const p = page("start-te-timer-mode", "0:00:00");
    let opened = false, selected = "";
    const name = { textContent: "Work", getAttribute: () => "#123456", click: () => { selected = "42"; opened = false; } };
    const row = {
        getAttribute: () => "select-project-42",
        querySelector: key => key.includes("ProjectName") ? name : null
    };
    const input = { value: "" };
    const grid = {
        scrollTop: 0, clientHeight: 300, scrollHeight: 600, textContent: "Work",
        querySelectorAll: () => [row],
        querySelector: key => key.includes("select-project-42") ? row : null
    };
    p.elements['[aria-label="Add a project"]'] = {
        querySelector: key => {
            if (key.includes("ProjectsContainer")) return opened ? grid : null;
            if (key === '[tabindex="0"]') return { click: () => { opened = true; } };
            if (key.includes("Overlay")) return { click: () => { opened = false; } };
            if (key === "input") return input;
            return null;
        }
    };
    return { ...p, grid, input, selected: () => selected,
        projects: (step, extra = {}) => p.send({ type: "projects", step, ...extra }) };
}

test("project DOM adapter reads IDs, names and colors without selecting", () => {
    const p = projectPicker();
    p.projects("open");
    expect(p.projects("read").projects).toEqual([{ id: "42", name: "Work", client: "", color: "#123456" }]);
    p.projects("scroll", { position: 300 });
    expect(p.grid.scrollTop).toBe(300);
    expect(p.selected()).toBe("");
    p.projects("close");
    expect(p.projects("read").loading).toBe(true);
});
test("project selection clicks the name, never the pin button or the timer", () => {
    const p = projectPicker();
    p.projects("open");
    expect(p.projects("select", { projectId: "42" }).ok).toBe(true);
    expect(p.selected()).toBe("42");
    expect(p.clicks()).toBe(0);
});
test("invalid project IDs and active project searches fail closed", () => {
    const p = projectPicker();
    p.projects("open");
    expect(p.projects("select", { projectId: '42"]' }).error).toBeTruthy();
    expect(p.projects("select", { projectId: "99" }).error).toBeTruthy();
    p.input.value = "search in progress";
    expect(p.projects("read").error).toBeTruthy();
    expect(p.selected()).toBe("");
});

test("hidden retained picker is reopened instead of cached as a complete list", () => {
    const p = projectPicker();
    p.projects("open");
    p.grid.getClientRects = () => [];
    expect(p.projects("read").loading).toBe(true);
    p.grid.getClientRects = () => [{ height: 300 }];
    expect(p.projects("read").projects).toHaveLength(1);
});
