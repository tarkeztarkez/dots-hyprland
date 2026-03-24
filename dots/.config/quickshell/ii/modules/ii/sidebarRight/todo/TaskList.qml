import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var taskList
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText
    property int todoListItemSpacing: 5
    property int todoListItemPadding: 8
    property int listBottomPadding: 80

    function dueText(task) {
        if (!task?.due?.string) {
            return "";
        }
        return task.due.string;
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        spacing: root.todoListItemSpacing
        animateAppearance: false
        model: ScriptModel {
            values: root.taskList
        }
        delegate: Item {
            id: todoItem
            required property var modelData
            implicitHeight: todoRow.implicitHeight + separatorRect.implicitHeight + 6
            width: ListView.view.width
            clip: true

            RowLayout {
                id: todoRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                anchors.topMargin: 4
                spacing: 10

                RippleButton {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 24
                    implicitHeight: 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                    onClicked: {
                        if (!todoItem.modelData.done)
                            Todo.markDone(todoItem.modelData.id);
                        else
                            Todo.markUnfinished(todoItem.modelData.id);
                    }

                    contentItem: Item {
                        anchors.fill: parent

                        Rectangle {
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            radius: width / 2
                            color: todoItem.modelData.done ? Appearance.colors.colPrimary : "transparent"
                            border.width: 2
                            border.color: todoItem.modelData.done ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "check"
                            iconSize: 14
                            color: todoItem.modelData.done ? Appearance.m3colors.m3onPrimary : "transparent"
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    StyledText {
                        Layout.fillWidth: true
                        text: todoItem.modelData.content
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.strikeout: todoItem.modelData.done
                    }

                    StyledText {
                        visible: text.length > 0
                        Layout.fillWidth: true
                        text: todoItem.modelData.description ?? ""
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    RowLayout {
                        visible: dueLabel.visible
                        spacing: 5

                        MaterialSymbol {
                            id: recurringIcon
                            visible: todoItem.modelData.due?.isRecurring ?? false
                            text: "repeat"
                            iconSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            id: dueLabel
                            visible: text.length > 0
                            text: root.dueText(todoItem.modelData)
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }

            Rectangle {
                id: separatorRect
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 34
                height: 1
                color: ColorUtils.transparentize(Appearance.m3colors.m3outlineVariant, 0.45)
            }
        }
    }

    Item {
        // Placeholder when list is empty
        visible: opacity > 0
        opacity: taskList.length === 0 ? 1 : 0
        anchors.fill: parent

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 55
                color: Appearance.m3colors.m3outline
                text: emptyPlaceholderIcon
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3outline
                horizontalAlignment: Text.AlignHCenter
                text: emptyPlaceholderText
            }
        }
    }
}
