import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris

// 悬浮详情面板（plasmusic-toolbar 样式）：封面 + 歌名/歌手 + 进度条 + 控制按钮 + 歌词
// 由 main.qml 注入 widget（PlasmoidItem）访问 MPRIS 数据
Item {
    id: root

    property QtObject applet: null

    implicitWidth: 280
    // 有歌词 → 展开歌词区（200）；无歌词 → 收缩为原紧凑样式（100）
    implicitHeight: root.applet.hasLyrics ? 200 : 100

    // 背景
    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Qt.rgba(0.12, 0.12, 0.16, 0.95)
        border.color: Qt.rgba(1, 1, 1, 0.15)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 5

        // ================= 上半部分：封面 + 信息 + 控制 =================
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            Layout.alignment: root.applet.hasLyrics ? Qt.AlignTop : Qt.AlignVCenter
            spacing: 12

            // 左：封面（圆形唱片，播放时像黑胶一样旋转）
            Item {
                id: coverDisc
                width: 64
                height: 64
                Layout.alignment: Qt.AlignVCenter

                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: 3200
                    loops: Animation.Infinite
                    running: root.applet.playbackStatus === Mpris.PlaybackStatus.Playing
                }

                // 封面图（圆形裁剪）
                Image {
                    id: coverImg
                    anchors.fill: parent
                    source: root.applet.artUrl
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Item {
                            width: coverDisc.width
                            height: coverDisc.height
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                            }
                        }
                    }
                    visible: root.applet.ready && status === Image.Ready
                }
                // 无封面时的灰色占位圆
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.rgba(0.25, 0.25, 0.3, 1)
                    visible: !coverImg.visible
                }
            }

            // 右：歌名/歌手 + 进度 + 控制
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                Text {
                    text: root.applet.ready ? root.applet.title : i18n("未在播放")
                    color: "white"
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: root.applet.ready ? root.applet.artists : i18n("无媒体播放")
                    color: Qt.rgba(1, 1, 1, 0.7)
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    Layout.fillWidth: true
                }

                // 进度条 + 时间
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: root.applet.formatTime(root.applet.songPosition)
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.pixelSize: 10
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.25)
                        Rectangle {
                            width: parent.width * root.applet.progress
                            height: 4
                            radius: 2
                            color: Kirigami.Theme.highlightColor
                        }
                    }
                    Text {
                        text: root.applet.formatTime(root.applet.songLength)
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.pixelSize: 10
                    }
                }

                // 控制按钮
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    PlasmaComponents3.ToolButton {
                        hoverEnabled: true
                        icon.name: "media-skip-backward"
                        onClicked: {
                            if (root.applet.player) {
                                root.applet.player.Previous()
                            }
                        }
                    }
                    PlasmaComponents3.ToolButton {
                        hoverEnabled: true
                        icon.name: root.applet.playbackStatus === Mpris.PlaybackStatus.Playing ? "media-playback-pause" : "media-playback-start"
                        onClicked: root.applet.playPause()
                    }
                    PlasmaComponents3.ToolButton {
                        hoverEnabled: true
                        icon.name: "media-skip-forward"
                        onClicked: {
                            if (root.applet.player) {
                                root.applet.player.Next()
                            }
                        }
                    }
                }
            }
        }

        // 分隔线（有歌词时显示）
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(1, 1, 1, 0.12)
            visible: root.applet.hasLyrics
        }

        // ================= 下半部分：歌词（三行：上一句/当前/下一句，淡出淡入） =================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            visible: root.applet.hasLyrics

            ListView {
                id: lyricsView
                anchors.fill: parent
                model: root.applet.lyricsModel
                currentIndex: root.applet.lyricsIndex
                spacing: 2
                clip: true
                cacheBuffer: 300

                delegate: Item {
                    width: lyricsView.width
                    height: 28

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        text: model.text
                        color: "white"
                        // 当前行最亮，前/后一句淡出，其余几乎不可见
                        opacity: index === lyricsView.currentIndex ? 1.0 : (Math.abs(index - lyricsView.currentIndex) === 1 ? 0.42 : 0.15)
                        font.pixelSize: index === lyricsView.currentIndex ? 13 : 11.5
                        font.bold: index === lyricsView.currentIndex
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                        Behavior on font.pixelSize { NumberAnimation { duration: 300 } }
                    }
                }

                // 平滑滚动：当前行居中，露出上/下一句
                onCurrentIndexChanged: {
                    var item = currentItem
                    if (item) {
                        var target = item.y + item.height / 2 - lyricsView.height / 2
                        animateScroll.to = Math.max(0, Math.min(target, lyricsView.contentHeight - lyricsView.height))
                        animateScroll.restart()
                    }
                }

                NumberAnimation {
                    id: animateScroll
                    target: lyricsView
                    property: "contentY"
                    duration: 350
                    easing.type: Easing.OutCubic
                }
            }

            // 无歌词时的提示
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4
                visible: root.applet.lyricsModel.count === 0

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    source: "media-playlist-none"
                    color: Qt.rgba(1, 1, 1, 0.35)
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: i18n("暂无歌词")
                    color: Qt.rgba(1, 1, 1, 0.4)
                    font.pixelSize: 10
                }
            }
        }
    }
}
