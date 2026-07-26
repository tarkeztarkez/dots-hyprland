import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledPopup {
    id: root

    property var serverState: ({ mode: "auto", activeEmail: null, accounts: [] })
    property string errorMessage: ""
    readonly property int tableWidth: 520

    function percentage(value) {
        return value === null || value === undefined ? "—" : `${Math.round(value)}%`;
    }

    function prettyStatus(value) {
        if (!value)
            return "unknown";
        return String(value).replace(/_/g, " ");
    }

    function statusColor(account) {
        if (account.status === "error" || account.status === "relogin_required" || account.status === "depleted")
            return Appearance.m3colors.m3error;
        if (account.status === "low_limit")
            return Appearance.m3colors.m3tertiary;
        return Appearance.m3colors.m3primary;
    }

    Item {
        implicitWidth: root.tableWidth
        implicitHeight: tableContent.implicitHeight

        ColumnLayout {
            id: tableContent
            anchors.centerIn: parent
            width: root.tableWidth
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                MaterialSymbol {
                    text: "token"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.m3colors.m3primary
                }

                ColumnLayout {
                    spacing: 0

                    StyledText {
                        text: "Codex usage limits"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        text: root.serverState.activeEmail ? `Current: ${root.serverState.activeEmail}` : "No account selected"
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: modeLabel.implicitWidth + 16
                    implicitHeight: modeLabel.implicitHeight + 8
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer

                    StyledText {
                        id: modeLabel
                        anchors.centerIn: parent
                        text: (root.serverState.mode ?? "unknown").toUpperCase()
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    StyledText { text: ""; Layout.preferredWidth: 16 }
                    StyledText { text: "ACCOUNT"; Layout.preferredWidth: 220; font.weight: Font.DemiBold; color: Appearance.colors.colOnSurfaceVariant }
                    StyledText { text: "5 HOUR"; Layout.preferredWidth: 58; horizontalAlignment: Text.AlignRight; font.weight: Font.DemiBold; color: Appearance.colors.colOnSurfaceVariant }
                    StyledText { text: "WEEKLY"; Layout.preferredWidth: 58; horizontalAlignment: Text.AlignRight; font.weight: Font.DemiBold; color: Appearance.colors.colOnSurfaceVariant }
                    StyledText { text: "STATUS"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; font.weight: Font.DemiBold; color: Appearance.colors.colOnSurfaceVariant }
                }
            }

            Repeater {
                model: root.serverState.accounts ?? []

                delegate: Rectangle {
                    id: accountRow
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Appearance.rounding.small
                    color: modelData.active ? Appearance.colors.colSecondaryContainer : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        MaterialSymbol {
                            Layout.preferredWidth: 16
                            text: accountRow.modelData.active ? "check_circle" : "circle"
                            iconSize: Appearance.font.pixelSize.normal
                            color: accountRow.modelData.active ? Appearance.m3colors.m3primary : Appearance.colors.colOutlineVariant
                        }
                        StyledText {
                            Layout.preferredWidth: 220
                            text: accountRow.modelData.email
                            elide: Text.ElideRight
                            font.weight: accountRow.modelData.active ? Font.DemiBold : Font.Normal
                            color: accountRow.modelData.active ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnSurface
                        }
                        StyledText { Layout.preferredWidth: 58; text: root.percentage(accountRow.modelData.fiveHourRemaining); horizontalAlignment: Text.AlignRight; color: root.statusColor(accountRow.modelData) }
                        StyledText { Layout.preferredWidth: 58; text: root.percentage(accountRow.modelData.weeklyRemaining); horizontalAlignment: Text.AlignRight; color: root.statusColor(accountRow.modelData) }
                        StyledText { Layout.fillWidth: true; text: root.prettyStatus(accountRow.modelData.status); horizontalAlignment: Text.AlignRight; color: root.statusColor(accountRow.modelData) }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.errorMessage !== ""
                text: root.errorMessage
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.m3colors.m3error
            }

            StyledText {
                Layout.fillWidth: true
                visible: !root.errorMessage && (root.serverState.accounts?.length ?? 0) === 0
                text: "No accounts returned by the server"
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }
}
