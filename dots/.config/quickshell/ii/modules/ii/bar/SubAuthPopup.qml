import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

SubAuthStyledPopup {
    id: root

    popupRightMargin: 75
    property var serverState: ({ mode: "auto", activeEmail: null, accounts: [], total: ({}), dailyBudget: ({}) })
    property string errorMessage: ""
    readonly property int tableWidth: 570
    readonly property int accountColumnWidth: 175
    readonly property int fiveHourColumnWidth: 90
    readonly property int weeklyColumnWidth: 110

    function percentage(value) {
        return value === null || value === undefined ? "—" : `${Math.round(value)}%`;
    }

    function resetIn(value) {
        if (!value)
            return "—";
        let seconds = Math.max(0, Math.ceil((Date.parse(value) - Date.now()) / 1000));
        if (!isFinite(seconds) || seconds === 0)
            return "now";
        const days = Math.floor(seconds / 86400);
        seconds %= 86400;
        const hours = Math.floor(seconds / 3600);
        seconds %= 3600;
        const minutes = Math.max(1, Math.ceil(seconds / 60));
        if (days)
            return `${days}d ${hours}h`;
        if (hours)
            return `${hours}h ${minutes}m`;
        return `${minutes}m`;
    }

    function limit(value, resetAt) {
        if (value === null || value === undefined)
            return "—";
        return `${root.percentage(value)} · ${root.resetIn(resetAt)}`;
    }

    function totalLimit(limit) {
        if (!limit || limit.remaining === null || limit.remaining === undefined)
            return "—";
        const count = limit.totalAccountCount > 0 ? ` (${limit.accountCount}/${limit.totalAccountCount})` : "";
        return `${root.percentage(limit.remaining)} LEFT${count}`;
    }

    function dailyCountdown(value) {
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

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: Appearance.rounding.small
                color: Appearance.colors.colSecondaryContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 4
                    anchors.bottomMargin: 4
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol { Layout.preferredWidth: 16; text: "functions"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.m3colors.m3primary }
                        StyledText { Layout.preferredWidth: root.accountColumnWidth; text: "TOTAL"; font.weight: Font.Bold; color: Appearance.m3colors.m3onSecondaryContainer }
                        StyledText { Layout.preferredWidth: root.fiveHourColumnWidth; text: root.totalLimit(root.serverState.total?.fiveHour); horizontalAlignment: Text.AlignRight; font.weight: Font.DemiBold; color: Appearance.m3colors.m3onSecondaryContainer }
                        StyledText { Layout.preferredWidth: root.weeklyColumnWidth; text: root.totalLimit(root.serverState.total?.weekly); horizontalAlignment: Text.AlignRight; font.weight: Font.DemiBold; color: Appearance.m3colors.m3onSecondaryContainer }
                        StyledText { Layout.fillWidth: true; text: "" }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: `TODAY LEFT  ·  ALL DAYS ${root.dailyCountdown(root.serverState.dailyBudget?.allDaysRemaining)}  ·  WEEKDAYS ${root.dailyCountdown(root.serverState.dailyBudget?.weekdaysRemaining)}`
                        horizontalAlignment: Text.AlignRight
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3primary
                    }
                }
            }

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
                    StyledText { text: "ACCOUNT"; Layout.preferredWidth: root.accountColumnWidth; font.weight: Font.DemiBold; color: Appearance.colors.colOnSurfaceVariant }
                    StyledText { text: "5H · RESET"; Layout.preferredWidth: root.fiveHourColumnWidth; horizontalAlignment: Text.AlignRight; font.weight: Font.DemiBold; color: Appearance.colors.colOnSurfaceVariant }
                    StyledText { text: "WEEK · RESET"; Layout.preferredWidth: root.weeklyColumnWidth; horizontalAlignment: Text.AlignRight; font.weight: Font.DemiBold; color: Appearance.colors.colOnSurfaceVariant }
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
                            Layout.preferredWidth: root.accountColumnWidth
                            text: accountRow.modelData.email
                            elide: Text.ElideRight
                            font.weight: accountRow.modelData.active ? Font.DemiBold : Font.Normal
                            color: accountRow.modelData.active ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnSurface
                        }
                        StyledText { Layout.preferredWidth: root.fiveHourColumnWidth; text: root.limit(accountRow.modelData.fiveHourRemaining, accountRow.modelData.fiveHourResetAt); horizontalAlignment: Text.AlignRight; color: root.statusColor(accountRow.modelData) }
                        StyledText { Layout.preferredWidth: root.weeklyColumnWidth; text: root.limit(accountRow.modelData.weeklyRemaining, accountRow.modelData.weeklyResetAt); horizontalAlignment: Text.AlignRight; color: root.statusColor(accountRow.modelData) }
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
