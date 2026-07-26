import QtQuick
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

MouseArea {
    id: root

    property var serverState: ({ mode: "auto", activeEmail: null, accounts: [] })
    property string errorMessage: ""
    readonly property var activeAccount: serverState.accounts?.find(account => account.active) ?? null

    implicitWidth: 28
    implicitHeight: Appearance.sizes.baseBarHeight
    hoverEnabled: true

    function refresh() {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function limitColor(account) {
        if (!account || account.status === "error" || account.status === "relogin_required")
            return Appearance.m3colors.m3error;
        const remaining = Math.min(account.fiveHourRemaining ?? 100, account.weeklyRemaining ?? 100);
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
            color: root.limitColor(root.activeAccount)
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: 6
            height: 6
            radius: 3
            color: root.errorMessage ? Appearance.m3colors.m3error : root.limitColor(root.activeAccount)
            border.width: 1
            border.color: Appearance.m3colors.m3surfaceContainer
        }
    }

    SubAuthPopup {
        hoverTarget: root
        serverState: root.serverState
        errorMessage: root.errorMessage
    }
}
