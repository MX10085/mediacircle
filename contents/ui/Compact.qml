import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris

Item {
    id: compact

    // 暴露给 main.qml 的兜底收起检查：鼠标是否还在图标上
    property alias hovered: hoverHandler.hovered

    // 抗锯齿（解决锯齿严重的问题）
    antialiasing: true

    readonly property bool horizontal: widget.formFactor === PlasmaCore.Types.Horizontal
    readonly property bool planar: widget.formFactor === PlasmaCore.Types.Planar
    // 面板厚度：横向面板=自身高度（由面板约束），侧边栏=宽度
    readonly property real thickness: horizontal ? height : width
    // 圆直径：面板上=面板厚度；桌面=固定 48
    readonly property real diameter: planar ? 48 : Math.min(width, height)
    readonly property real ringWidth: Math.max(3, diameter * 0.11)
    readonly property real innerR: diameter / 2 - ringWidth / 2 - 1
    // 唱片直径（进度环内侧再留 1px 空隙；取偶整数像素，与环圆心精确对齐防偏心）
    readonly property real recordSize: Math.round(innerR - 1) * 2
    // 标签（封面）直径 = 唱片 90%（取偶整数像素）
    readonly property real labelSize: Math.round(recordSize * 0.90 / 2) * 2

    // 宽度 = 厚度（圆形），高度由面板约束；给 28 兜底防布局顺序算出 0
    Layout.preferredWidth: planar ? 48 : Math.max(thickness, 28)
    Layout.preferredHeight: planar ? 48 : Math.max(thickness, 28)
    Layout.minimumWidth: Layout.preferredWidth
    Layout.minimumHeight: Layout.preferredHeight

    // ============ 进度环（Canvas 绘制，12 点起顺时针，场景图自带抗锯齿） ============
    // 注意：不要用 layer（Shape 进 FBO 会丢失抗锯齿，锯齿反而更严重）
    Canvas {
        id: ring
        anchors.fill: parent
        visible: widget.ready && widget.songLength > 0
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = Math.floor(width / 2)
            var cy = Math.floor(height / 2)
            ctx.lineWidth = compact.ringWidth
            ctx.lineCap = "round"
            // 底环
            ctx.strokeStyle = "rgba(0, 0, 0, 0.35)"
            ctx.beginPath()
            ctx.arc(cx, cy, compact.innerR, 0, Math.PI * 2)
            ctx.stroke()
            // 进度弧（从 12 点方向起，顺时针）
            ctx.strokeStyle = Kirigami.Theme.highlightColor
            ctx.beginPath()
            ctx.arc(cx, cy, compact.innerR, -Math.PI / 2, -Math.PI / 2 + widget.progress * Math.PI * 2)
            ctx.stroke()
        }

        Connections {
            target: widget
            function onProgressChanged() { ring.requestPaint() }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    // ============ 黑胶唱片主体（播放时旋转） ============
    Item {
        id: record
        width: compact.recordSize
        height: compact.recordSize
        anchors.centerIn: parent
        visible: widget.ready

        // 唱片盘（黑胶 + 沟槽）
        Rectangle {
            id: disc
            anchors.fill: parent
            radius: width / 2
            color: "#141418"
            antialiasing: true

            // 沟槽：3 道同心细环（贴在唱片外圈，封面变大后留白更合理）
            Repeater {
                model: 3
                Rectangle {
                    width: record.width * (0.94 - index * 0.04)
                    height: width
                    anchors.centerIn: disc
                    radius: width / 2
                    color: "transparent"
                    border.width: Math.max(0.6, compact.diameter * 0.02)
                    border.color: Qt.rgba(0.45, 0.45, 0.5, 0.45)
                    antialiasing: true
                }
            }

            // 唱片反光（顶部高光 → 底部微暗）
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.09) }
                    GradientStop { position: 0.18; color: Qt.rgba(1, 1, 1, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.28) }
                }
            }
        }

        // 中心标签 = 当前歌曲封面（圆形裁剪，4x 超采样保清晰）
        Image {
            id: label
            width: compact.labelSize
            height: compact.labelSize
            // 显式整数坐标居中（避免 layer 浮点渲染与唱片像素对齐错位）
            x: Math.round((record.width - width) / 2)
            y: Math.round((record.height - height) / 2)
            source: widget.artUrl
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(compact.labelSize * 4 * Screen.devicePixelRatio, compact.labelSize * 4 * Screen.devicePixelRatio)
            smooth: true
            layer.enabled: true
            layer.smooth: true
            // 纹理 = labelSize 的精确 4 倍（整数缩放，圆心精确对齐，不偏心）
            layer.textureSize: Qt.size(compact.labelSize * 4, compact.labelSize * 4)
            layer.effect: OpacityMask {
                maskSource: Item {
                    width: label.width
                    height: label.height
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        antialiasing: true
                    }
                }
            }
            visible: widget.ready && status === Image.Ready
        }

        // 无封面时标签底色
        Rectangle {
            anchors.fill: label
            radius: width / 2
            color: Qt.rgba(0.30, 0.30, 0.36, 1)
            antialiasing: true
            visible: !label.visible
        }

        // 唱片旋转：播放时转（33⅓ RPM 视觉）
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 3200
            loops: Animation.Infinite
            running: widget.playbackStatus === Mpris.PlaybackStatus.Playing
        }
    }

    // ============ 中间播放键（暂停/停止时显示，播放中隐藏露出旋转唱片） ============
    Rectangle {
        id: btnBg
        anchors.centerIn: parent
        width: compact.labelSize * 0.62
        height: compact.labelSize * 0.62
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.5)
        border.color: Qt.rgba(1, 1, 1, 0.22)
        border.width: 1
        visible: widget.ready && widget.playbackStatus !== Mpris.PlaybackStatus.Playing
    }

    Kirigami.Icon {
        anchors.centerIn: btnBg
        width: compact.labelSize * 0.42
        height: compact.labelSize * 0.42
        source: "media-playback-start"
        color: "white"
        visible: btnBg.visible
    }

    // ============ 无媒体时的占位：Spotify 官方 logo ============
    Item {
        id: placeholder
        anchors.fill: parent
        anchors.margins: compact.ringWidth / 2 + 0.5
        visible: !widget.ready

        Image {
            anchors.fill: parent
            anchors.margins: Math.round(parent.width * 0.08)
            source: "file:///usr/share/icons/Papirus-Dark/128x128/apps/spotify.svg"
            sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }

    // ============ 交互：左键播放/暂停，滚轮音量，中键唤起，侧键切歌；悬浮弹出详情 ============
    // 用 HoverHandler/TapHandler/WheelHandler 替代 MouseArea：
    // MouseArea 会吃光鼠标事件，导致 Plasma 编辑模式下小部件无法被拖动；
    // 这些 Handler 只认"悬停/点击/滚轮"，不拦截拖动，编辑模式下可正常移动小部件。
    HoverHandler {
        id: hoverHandler
        onHoveredChanged: {
            if (hovered) {
                widget.expandPopup()
            } else {
                widget.scheduleCollapse()
            }
        }
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: {
            if (widget.ready) {
                widget.playPause()
            }
        }
    }
    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: {
            if (widget.player) {
                widget.player.Raise()
            }
        }
    }
    TapHandler {
        acceptedButtons: Qt.BackButton
        onTapped: {
            if (widget.player && widget.player.canGoPrevious) {
                widget.player.Previous()
            }
        }
    }
    TapHandler {
        acceptedButtons: Qt.ForwardButton
        onTapped: {
            if (widget.player && widget.player.canGoNext) {
                widget.player.Next()
            }
        }
    }
    WheelHandler {
        onWheel: (event) => {
            if (widget.player) {
                const delta = event.angleDelta.y > 0 ? 0.05 : -0.05
                widget.player.changeVolume(delta, true)
            }
        }
    }
}
