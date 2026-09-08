import { test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const context = {};
runInNewContext(readFileSync(new URL("../../../.config/quickshell/ii/services/TogglOptimistic.js", import.meta.url), "utf8"), context);
const server = { available: true, running: false, sampledAt: 100, pending: false, commandId: "old" };

test("project start and stop update immediately", () => {
    expect(context.begin("start", { name: "Work" }, 100, "new")).toMatchObject({ running: true, title: "Work", elapsed: 0 });
    expect(context.begin("stop", null, 100, "stop").running).toBe(false);
});
test("old polls cannot overwrite an optimistic action", () => {
    const pending = context.begin("start", { name: "Work" }, 100, "new");
    expect(context.reconcile(pending, server, 101).value).toBe(pending);
    expect(context.reconcile(pending, { ...server, commandId: "new", pending: true }, 101).value).toBe(pending);
});
test("matching confirmation replaces optimistic state with server data", () => {
    const pending = context.begin("start", { name: "Work" }, 100, "new");
    expect(context.reconcile(pending, { ...server, commandId: "new", running: true }, 101)).toEqual({ value: null, error: "" });
});
test("failure rolls back rather than leaving a fake timer running", () => {
    const pending = context.begin("start", { name: "Work" }, 100, "new");
    expect(context.reconcile(pending, { ...server, commandId: "new", error: "Project removed" }, 101)).toEqual({ value: null, error: "Project removed" });
});
test("disconnect, stale data and timeout all roll back", () => {
    const pending = context.begin("start", { name: "Work" }, 100, "new");
    for (const [data, now] of [[{ ...server, available: false }, 101], [server, 113], [{ ...server, sampledAt: 121 }, 121]]) {
        const result = context.reconcile(pending, data, now);
        expect(result.value).toBeNull();
        expect(result.error).toBeTruthy();
    }
});
