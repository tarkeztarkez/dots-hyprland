import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

MouseArea {
    id: root
    property var tracker: TogglTrack
    property bool menuOpen: false
    Layout.fillHeight: true
    implicitWidth: Math.min(200, contentLayout.implicitWidth)
    implicitHeight: Appearance.sizes.barHeight
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: root.tracker.available ? Qt.PointingHandCursor : Qt.ArrowCursor

    function openProjects() {
        if (!root.tracker.available || root.tracker.running) return;
        menuOpen = true;
        root.tracker.loadProjects();
    }

    function startProject(project) {
        if (!root.tracker.available || root.tracker.pending) return;
        menuOpen = false;
        root.tracker.act("start", project);
    }

    onEntered: {
        closeDelay.stop();
        openProjects();
    }
    onExited: closeDelay.restart()
    onClicked: event => {
        if (event.button === Qt.RightButton) root.tracker.act("open");
        else if (root.tracker.running) root.tracker.act("stop");
        else openProjects();
    }
    ToolTip.visible: containsMouse && !menuOpen
    ToolTip.delay: 600
    ToolTip.text: root.tracker.detail
    Accessible.name: "Toggl Track, " + root.tracker.title + (root.tracker.running ? ", " + root.tracker.duration : "")
    Accessible.role: Accessible.Button

    Connections {
        target: root.tracker
        function onRunningChanged() {
            if (root.tracker.running) root.menuOpen = false;
            else if (root.containsMouse) root.openProjects();
        }
        function onAvailableChanged() {
            if (!root.tracker.available) root.menuOpen = false;
        }
        function onPendingChanged() {
            if (!root.tracker.pending && root.menuOpen) root.tracker.loadProjects();
        }
    }

    Timer {
        id: closeDelay
        interval: 350
        onTriggered: {
            if (!root.containsMouse && !menuLoader.item?.hovered) root.menuOpen = false;
        }
    }

    RowLayout {
        id: contentLayout
        anchors.fill: parent
        spacing: 6
        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: !root.tracker.available ? "timer_off" : root.tracker.running ? "stop_circle" : "timer"
            iconSize: 20
            color: root.tracker.running ? Appearance.m3colors.m3primary : Appearance.colors.colOnLayer1
            opacity: root.tracker.optimistic ? 0.65 : 1
        }
        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.tracker.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            visible: root.tracker.running
            Layout.alignment: Qt.AlignVCenter
            text: root.tracker.duration
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colOnLayer1
        }
    }

    Loader {
        id: menuLoader
        active: root.menuOpen && root.QsWindow.window !== null
        sourceComponent: PopupWindow {
        id: menu
        readonly property bool hovered: menuHover.hovered
        visible: true
        color: "transparent"
        implicitWidth: 300
        implicitHeight: Math.min(420, menuColumn.implicitHeight + 20)
        anchor {
            window: root.QsWindow.window
            item: root
            edges: Config.options.bar.bottom ? Edges.Top : Edges.Bottom
            gravity: Config.options.bar.bottom ? Edges.Top : Edges.Bottom
        }

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            HoverHandler {
                id: menuHover
                onHoveredChanged: {
                    if (hovered) closeDelay.stop();
                    else closeDelay.restart();
                }
            }

            ColumnLayout {
                id: menuColumn
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: 10
                }
                spacing: 6
                StyledText {
                    text: "Start a timer"
                    font.bold: true
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.tracker.loadingProjects || root.tracker.projects.length === 0 || root.tracker.localError !== "" || root.tracker.state.error
                    text: root.tracker.localError || root.tracker.state.error || (root.tracker.loadingProjects ? "Loading projects..." : "No projects. Open Toggl to check your workspace.")
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: root.tracker.localError || root.tracker.state.error ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                }
                ListView {
                    id: projectList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(320, contentHeight)
                    clip: true
                    model: root.tracker.projects
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        id: entry
                        required property var modelData
                        width: projectList.width
                        height: 42
                        radius: Appearance.rounding.small
                        color: projectMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: /^#[0-9a-fA-F]{6}$/.test(entry.modelData.color) ? entry.modelData.color : Appearance.m3colors.m3primary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: entry.modelData.name
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer1
                            }
                            MaterialSymbol {
                                text: "play_arrow"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        MouseArea {
                            id: projectMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.tracker.pending
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.startProject(entry.modelData)
                        }
                    }
                }
            }
        }
    }
    }
}
