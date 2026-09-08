// Standalone visual fixture. It never sends commands to Helium.
// Run: quickshell -p ~/.config/quickshell/ii/toggl-widget-test.qml
//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import Quickshell
import Quickshell.Io
import "modules/common"
import "modules/ii/bar"

ShellRoot {
    QtObject {
        id: fixture
        property bool available: true
        property bool running: false
        property bool pending: false
        property bool loadingProjects: false
        property var optimistic: null
        property var state: ({ error: "" })
        property string localError: ""
        property string title: running ? selected : available ? "Toggl ready" : "Unavailable"
        property string selected: ""
        property string duration: "00:00:00"
        property string detail: "Visual test only"
        property string lastAction: ""
        property var projects: [
            { id: "1", name: "BEST", color: "#f66363" },
            { id: "2", name: "GoPay Planner", color: "#c9d599" },
            { id: "3", name: "GoPay Zlecenie", color: "#87e769" },
            { id: "4", name: "Verestro", color: "#48adf6" }
        ]
        function loadProjects() {}
        function act(action, project) {
            lastAction = action + (project ? ":" + project.id : "");
            if (action === "start") {
                selected = project.name;
                running = true;
            } else if (action === "stop") running = false;
        }
    }
    FloatingWindow {
        title: "Toggl widget test"
        visible: true
        implicitWidth: 340
        implicitHeight: 70
        color: Appearance.colors.colLayer0
        TogglWidget {
            id: widget
            anchors.fill: parent
            anchors.margins: 10
            tracker: fixture
        }
    }
    IpcHandler {
        target: "togglWidgetTest"
        function idle(): void { fixture.available = true; fixture.running = false; }
        function unavailable(): void { fixture.available = false; }
        function menu(): void { widget.openProjects(); }
        function start(index: int): void { widget.startProject(fixture.projects[index]); }
        function stop(): void { fixture.act("stop"); }
        function status(): string {
            return JSON.stringify({ available: fixture.available, running: fixture.running, menu: widget.menuOpen, action: fixture.lastAction });
        }
    }
}
