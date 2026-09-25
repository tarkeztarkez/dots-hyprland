import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common as C

NestableObject {
    id: root

    required property HyprlandMonitor monitor
    readonly property var liveMonitorData: HyprlandData.monitors.find(m => m.id === monitor.id)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    readonly property int activeWorkspace: monitor?.activeWorkspace?.id ?? 1
    readonly property bool currentWorkspaceNotFake: activeWindow?.activated ?? false // Active empty workspace = fake. At least, that's how I like to call it.
    readonly property int fakeWorkspace: currentWorkspaceNotFake ? -9999 : activeWorkspace
    readonly property int alwaysShown: C.Config.options.bar.workspaces.alwaysShown
    // Workspaces 1..alwaysShown, then only occupied ones (plus the active one so the indicator has a slot)
    property list<int> shownIds: []
    readonly property int shownCount: shownIds.length
    property int activeIndex: 0
    readonly property var specialWorkspace: liveMonitorData?.specialWorkspace
    readonly property string specialWorkspaceName: specialWorkspace?.name.replace("special:", "") ?? "special"
    readonly property bool specialWorkspaceActive: specialWorkspaceName !== ""

    property list<bool> occupied: []
    property list<var> biggestWindow: occupied.map((_, index) => {
        const wsId = getWorkspaceIdAt(index);
        var biggestWindow = HyprlandData.biggestWindowForWorkspace(wsId);
        return biggestWindow;
    })

    function getWorkspaceIdAt(index) {
        return root.shownIds[index] ?? -1;
    }

    // Function to update shownIds and workspaceOccupied
    function updateWorkspaceOccupied() {
        const existing = Hyprland.workspaces.values.map(ws => ws.id).filter(id => id > 0);
        const ids = new Set(existing);
        for (let i = 1; i <= root.alwaysShown; i++)
            ids.add(i);
        if (root.activeWorkspace > 0)
            ids.add(root.activeWorkspace);
        const sorted = Array.from(ids).sort((a, b) => a - b);
        root.shownIds = sorted;
        root.activeIndex = Math.max(0, sorted.indexOf(root.activeWorkspace));
        root.occupied = root.shownIds.map(id => existing.includes(id));
    }

    // Occupied workspace updates
    Component.onCompleted: updateWorkspaceOccupied()
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            root.updateWorkspaceOccupied();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.updateWorkspaceOccupied();
        }
    }
    onActiveWorkspaceChanged: updateWorkspaceOccupied()
    onAlwaysShownChanged: updateWorkspaceOccupied()
}
