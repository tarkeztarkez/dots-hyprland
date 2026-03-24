pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string tdBinary: FileUtils.trimFileProtocol(`${Directories.home}/.bun/bin/td`)
    property var unfinishedList: []
    property var completedList: []
    property var list: unfinishedList
    property bool loading: false
    property bool mutating: mutateProc.running
    property string error: ""
    property int pendingRefreshes: 0
    property bool retryWanted: false

    Timer {
        id: deferredRefreshTimer
        interval: 0
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: retryRefreshTimer
        interval: 3000
        repeat: false
        onTriggered: root.refresh()
    }

    function setError(message) {
        if (root.error.length === 0) {
            root.error = message;
        }
        root.retryWanted = true;
        retryRefreshTimer.restart();
    }

    function normalizeTasks(results, done) {
        return (results ?? []).map(task => ({
            "id": task.id,
            "content": task.content ?? "",
            "description": task.description ?? "",
            "priority": task.priority ?? 1,
            "due": task.due ?? null,
            "deadline": task.deadline ?? null,
            "duration": task.duration ?? null,
            "projectId": task.projectId ?? null,
            "sectionId": task.sectionId ?? null,
            "parentId": task.parentId ?? null,
            "labels": task.labels ?? [],
            "url": task.url ?? "",
            "responsibleUid": task.responsibleUid ?? null,
            "isUncompletable": task.isUncompletable ?? false,
            "done": done,
        }));
    }

    function finishRefresh() {
        root.pendingRefreshes = Math.max(0, root.pendingRefreshes - 1);
        if (root.pendingRefreshes === 0) {
            root.loading = false;
            if (root.retryWanted) {
                retryRefreshTimer.restart();
            }
        }
    }

    function refresh() {
        if (root.loading || root.mutating) {
            return;
        }

        root.error = "";
        root.retryWanted = false;
        if (!tdAvailableProc.running && !root.tdAvailable) {
            tdAvailableProc.running = true;
            return;
        }
        root.loading = true;
        root.pendingRefreshes = 2;
        refreshTodayProc.running = true;
        refreshCompletedProc.running = true;
    }

    function addTask(desc) {
        const trimmed = desc.trim();
        if (trimmed.length === 0 || root.mutating) {
            return;
        }

        root.error = "";
        mutateProc.exec([root.tdBinary, "task", "add", "--project", "Inbox", "--due", "today", trimmed]);
    }

    function markDone(taskId) {
        if (!taskId || root.mutating) {
            return;
        }

        root.error = "";
        mutateProc.exec([root.tdBinary, "task", "complete", taskId]);
    }

    function markUnfinished(taskId) {
        if (!taskId || root.mutating) {
            return;
        }

        root.error = "";
        const ref = taskId.startsWith("id:") ? taskId : `id:${taskId}`;
        mutateProc.exec([root.tdBinary, "task", "uncomplete", ref]);
    }

    Component.onCompleted: {
        refresh();
    }

    property bool tdAvailable: false

    Process {
        id: tdAvailableProc
        command: ["test", "-x", root.tdBinary]

        onExited: (exitCode, exitStatus) => {
            root.tdAvailable = (exitCode === 0);
            if (!root.tdAvailable) {
                root.loading = false;
                root.setError(`Todoist CLI not found at ${root.tdBinary}`);
                return;
            }
            root.refresh();
        }
    }

    Process {
        id: refreshTodayProc
        command: [root.tdBinary, "today", "--json", "--all"]

        stdout: StdioCollector {
            id: refreshTodayCollector
            onStreamFinished: {
                try {
                    const payload = JSON.parse(refreshTodayCollector.text);
                    root.unfinishedList = root.normalizeTasks(payload.results, false);
                } catch (e) {
                    root.unfinishedList = [];
                    root.setError("Failed to parse Todoist today tasks.");
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.unfinishedList = [];
                root.setError("Failed to load Todoist today tasks.");
            }
            root.finishRefresh();
        }
    }

    Process {
        id: refreshCompletedProc
        command: [root.tdBinary, "completed", "--json", "--all"]

        stdout: StdioCollector {
            id: refreshCompletedCollector
            onStreamFinished: {
                try {
                    const payload = JSON.parse(refreshCompletedCollector.text);
                    root.completedList = root.normalizeTasks(payload.results, true);
                } catch (e) {
                    root.completedList = [];
                    root.setError("Failed to parse Todoist completed tasks.");
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.completedList = [];
                root.setError("Failed to load Todoist completed tasks.");
            }
            root.finishRefresh();
        }
    }

    Process {
        id: mutateProc
        command: ["true"]

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.setError("Todoist task action failed.");
                return;
            }
            deferredRefreshTimer.restart();
        }
    }
}
