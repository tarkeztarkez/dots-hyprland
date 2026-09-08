import QtQuick
import Quickshell
import Quickshell.Io
import "TogglOptimistic.js" as Optimistic
pragma Singleton

Singleton {
    id: root

    property var state: ({
        "available": false
    })
    property var optimistic: null
    property var projects: []
    property double projectsAt: 0
    property string projectRequest: ""
    property double projectDeadline: 0
    property string localError: ""
    property double now: Date.now() / 1000
    readonly property bool available: state.available === true && now - (state.sampledAt || 0) < 12
    readonly property bool running: available && (optimistic ? optimistic.running : state.running === true)
    readonly property bool pending: optimistic !== null || state.pending === true || control.running
    readonly property bool loadingProjects: projectRequest !== ""
    readonly property var displayState: optimistic || state
    readonly property int elapsed: available ? Math.max(0, (displayState.elapsed || 0) + (running ? Math.floor(now - displayState.sampledAt) : 0)) : 0
    readonly property string duration: Math.floor(elapsed / 3600).toString().padStart(2, "0") + ":" + Math.floor(elapsed % 3600 / 60).toString().padStart(2, "0") + ":" + (elapsed % 60).toString().padStart(2, "0")
    readonly property string title: !available ? "Unavailable" : running ? displayState.title || "No description" : "Toggl ready"
    readonly property string detail: localError || state.error || (!available ? state.reason || "Toggl is unavailable" : running ? "Click to stop. Right-click to open Toggl." : "Hover to choose a project. Right-click to open Toggl.")
    readonly property string bridge: Quickshell.env("HOME") + "/.local/share/toggl-bar/bridge.py"

    function receive(data) {
        state = data;
        if (data.projectsAt > 0) {
            projects = data.projects || [];
            projectsAt = data.projectsAt;
        }
        const result = Optimistic.reconcile(optimistic, data, now);
        optimistic = result.value;
        if (result.error)
            localError = result.error;

        if (!available || (data.commandId === projectRequest && !data.pending) || now >= projectDeadline)
            projectRequest = "";

    }

    function refresh() {
        if (!poll.running)
            poll.running = true;

    }

    function loadProjects() {
        if (available && !pending && !loadingProjects && (projects.length === 0 || now - projectsAt >= 300))
            act("projects");

    }

    function act(action, project) {
        if (pending || (action !== "open" && !available) || (action === "start" && !project))
            return ;

        const id = Date.now().toString() + "-" + Math.random().toString(36).slice(2);
        now = Date.now() / 1000;
        localError = "";
        if (action === "start" || action === "stop")
            optimistic = Optimistic.begin(action, project, now, id);

        if (action === "projects") {
            projectRequest = id;
            projectDeadline = now + 20;
        }
        control.command = ["python3", bridge, action, "--id", id, "--project", project ? project.id : ""];
        control.running = true;
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            root.now = Date.now() / 1000;
            const result = Optimistic.reconcile(root.optimistic, root.state, root.now);
            root.optimistic = result.value;
            if (result.error)
                root.localError = result.error;

            if (root.now >= root.projectDeadline)
                root.projectRequest = "";

            root.refresh();
        }
    }

    Process {
        id: poll

        command: ["python3", root.bridge, "status"]
        onExited: (code) => {
            if (code !== 0)
                root.receive({
                "available": false,
                "reason": "Toggl bridge is not installed"
            });

        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.receive(JSON.parse(text));
                } catch (_) {
                    root.receive({
                        "available": false,
                        "reason": "Could not read Toggl bridge"
                    });
                }
            }
        }

    }

    Process {
        id: control

        onExited: root.refresh()

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.receive(JSON.parse(text));
                } catch (_) {
                    root.optimistic = null;
                    root.localError = "Could not send command to Toggl";
                }
            }
        }

    }

}
