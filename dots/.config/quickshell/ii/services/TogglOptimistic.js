// Pure state transitions, shared with the regression tests.
function begin(action, project, now, id) {
    return { id: id, running: action === "start", title: project ? project.name : "",
        elapsed: 0, sampledAt: now, deadline: now + 20 };
}

function reconcile(optimistic, state, now) {
    if (!optimistic) return { value: null, error: "" };
    if (!state.available || now - (state.sampledAt || 0) >= 12)
        return { value: null, error: state.reason || "Toggl connection lost" };
    if (state.commandId === optimistic.id && !state.pending)
        return { value: null, error: state.error || (state.running !== optimistic.running ? "Toggl did not apply the change" : "") };
    if (now >= optimistic.deadline)
        return { value: null, error: "Toggl did not confirm the change. Check the page." };
    return { value: optimistic, error: "" };
}
