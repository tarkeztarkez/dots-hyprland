import QtQuick
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

MouseArea {
    id: root

    property var serverState: ({ mode: "auto", activeEmail: null, accounts: [], total: ({}), dailyBudget: ({}) })
    property string errorMessage: ""

    implicitWidth: 28
    implicitHeight: Appearance.sizes.baseBarHeight
    hoverEnabled: true

    function refresh() {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function totalRemaining() {
        const values = [];
        const five = root.serverState.total?.fiveHour?.remaining;
        const weekly = root.serverState.total?.weekly?.remaining;
        if (five !== null && five !== undefined)
            values.push(five);
        if (weekly !== null && weekly !== undefined)
            values.push(weekly);
        return values.length ? Math.min(...values) : null;
    }

    function totalLimitColor() {
        if (root.errorMessage)
            return Appearance.m3colors.m3error;
        const remaining = root.totalRemaining();
        if (remaining === null)
            return Appearance.colors.colOnSurfaceVariant;
        if (remaining < 10)
            return Appearance.m3colors.m3error;
        if (remaining < 25)
            return Appearance.m3colors.m3tertiary;
        return Appearance.m3colors.m3primary;
    }

    Component.onCompleted: refresh()
    onEntered: refresh()

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Process {
        id: statusProcess
        command: ["/usr/bin/env", "sub-auth", "status", "--json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.serverState = JSON.parse(text.trim());
                    root.errorMessage = "";
                } catch (error) {
                    root.errorMessage = "Could not read server response";
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.errorMessage = "Could not reach sub-auth server";
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 24
        height: 24
        radius: Appearance.rounding.full
        color: root.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

        MaterialSymbol {
            anchors.centerIn: parent
            text: "token"
            iconSize: Appearance.font.pixelSize.larger
            color: root.totalLimitColor()
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: 6
            height: 6
            radius: 3
            color: root.totalLimitColor()
            border.width: 1
            border.color: Appearance.m3colors.m3surfaceContainer
        }
    }

    Item {
        id: popupAnchor
        readonly property real popupBackgroundWidth: 590
        readonly property point rootPosition: root.QsWindow?.mapFromItem(root, 0, 0) ?? Qt.point(0, 0)
        x: {
            const windowWidth = root.QsWindow?.window?.width;
            if (!windowWidth)
                return -80;
            return windowWidth - rootPosition.x - width / 2 - popupBackgroundWidth / 2 - Appearance.sizes.elevationMargin * 2;
        }
        width: root.width
        height: root.height
        property bool containsMouse: root.containsMouse
    }

    SubAuthPopup {
        hoverTarget: popupAnchor
        serverState: root.serverState
        errorMessage: root.errorMessage
    }
}
