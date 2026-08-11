import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris

PlasmoidItem {
    id: widget

    // 一直显示在面板（无媒体时显示灰色图标，有媒体时显示封面）
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    // 不用默认背景框，圆形自绘
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // tooltip 已禁用：悬浮由 hoverDialog 详情面板接管
    toolTipMainText: ""
    toolTipSubText: ""

    // ---------------- MPRIS 数据 ----------------
    Mpris.Mpris2Model {
        id: mprisModel
        currentIndex: 0
    }

    readonly property var player: mprisModel.currentPlayer
    readonly property bool ready: !!(player && (player.track || player.artist || player.album))
    readonly property int playbackStatus: ready ? player.playbackStatus : Mpris.PlaybackStatus.Unknown
    readonly property string title: ready ? player.track : ""
    readonly property string artists: ready ? player.artist : ""
    // 封面兜底：当前播放器（如 Edge 原生 MPRIS）没给 artUrl 时，从其他 MPRIS 服务
    // （如 plasma-browser-integration）借封面。休眠恢复后服务重新枚举常见此情况。
    readonly property string artUrl: ready ? (player.artUrl || fallbackArtUrl) : ""
    // 其他 MPRIS 服务的最新封面（只读借用，不影响 currentPlayer 控制）
    property string fallbackArtUrl: ""
    readonly property double songPosition: ready ? player.position : 0
    readonly property double songLength: ready ? player.length : 0
    readonly property bool canPlay: ready ? player.canPlay : false
    readonly property bool canPause: ready ? player.canPause : false
    readonly property double progress: songLength > 0 ? Math.min(Math.max(songPosition / songLength, 0), 1) : 0

    // 遍历 MPRIS 模型，监听其他播放器的封面变化并缓存（Repeater delegate 可直接读角色）
    Repeater {
        id: artProbeRepeater
        model: mprisModel
        delegate: Item {
            property string probeArt: model.artUrl || ""
            onProbeArtChanged: {
                if (probeArt && probeArt !== widget.fallbackArtUrl) {
                    widget.fallbackArtUrl = probeArt
                }
            }
            Component.onCompleted: {
                if (probeArt && probeArt !== widget.fallbackArtUrl) {
                    widget.fallbackArtUrl = probeArt
                }
            }
        }
    }

    // ============ 歌词（在线获取 lrclib.net） ============
    property ListModel lyricsModel: ListModel {}
    property int lyricsIndex: -1
    property string currentLyricsKey: ""
    property var lyricsXhr: null
    readonly property string lyricsKey: ready ? player.track + "|" + player.artist : ""
    // 是否有歌词：决定悬浮面板是否展开歌词区
    readonly property bool hasLyrics: lyricsModel.count > 0

    onLyricsKeyChanged: widget.fetchLyrics()

    function fetchLyrics() {
        currentLyricsKey = lyricsKey
        lyricsModel.clear()
        lyricsIndex = -1
        if (!ready || !player.track) {
            return
        }
        var track = encodeURIComponent(player.track)
        var artist = encodeURIComponent(player.artist || "")
        var url = "https://lrclib.net/api/search?track_name=" + track + "&artist_name=" + artist
        if (lyricsXhr) {
            lyricsXhr.abort()
        }
        lyricsXhr = new XMLHttpRequest()
        lyricsXhr.onreadystatechange = function() {
            if (lyricsXhr.readyState === XMLHttpRequest.DONE) {
                if (lyricsXhr.status === 200) {
                    try {
                        var arr = JSON.parse(lyricsXhr.responseText)
                        var lrc = ""
                        if (arr.length > 0) {
                            lrc = arr[0].syncedLyrics || arr[0].plainLyrics || ""
                        }
                        widget.parseLrc(lrc)
                    } catch (e) {
                        widget.lyricsModel.clear()
                    }
                } else {
                    widget.lyricsModel.clear()
                }
            }
        }
        lyricsXhr.open("GET", url)
        lyricsXhr.send()
    }

    function parseLrc(text) {
        lyricsModel.clear()
        lyricsIndex = -1
        if (!text) {
            return
        }
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/\[(\d+):(\d+)(?:[.:](\d+))?\](.*)/)
            if (m) {
                var t = parseInt(m[1]) * 60000 + parseInt(m[2]) * 1000
                if (m[3]) {
                    var frac = m[3]
                    if (frac.length === 2) {
                        t += parseInt(frac) * 10
                    } else {
                        t += parseInt(frac)
                    }
                }
                var txt = m[4].trim()
                if (txt) {
                    lyricsModel.append({ time: t, text: txt })
                }
            }
        }
    }

    function updateLyrics() {
        if (lyricsModel.count === 0 || !ready) {
            return
        }
        var pos = player.position / 1000
        var idx = 0
        for (var i = 0; i < lyricsModel.count; i++) {
            if (lyricsModel.get(i).time <= pos) {
                idx = i
            } else {
                break
            }
        }
        if (idx !== lyricsIndex) {
            lyricsIndex = idx
        }
    }

    function playPause() {
        if (player) {
            player.PlayPause()
        }
    }

    function raisePlayer() {
        // 呼出正在播放的播放器主窗口（如浏览器播放页）
        if (player) {
            player.Raise()
        }
    }

    function updatePosition() {
        if (player) {
            player.updatePosition()
        }
    }

    function formatTime(us) {
        if (us <= 0) {
            return "0:00"
        }
        const s = Math.floor(us / 1000000)
        const m = Math.floor(s / 60)
        const sec = s % 60
        return m + ":" + (sec < 10 ? "0" : "") + sec
    }

    // ============ 悬浮弹出：鼠标悬停任务栏图标 → 上方弹出详情面板 ============
    function expandPopup() {
        // 编辑模式下不弹出悬浮面板：置顶窗口会挡住任务栏的编辑操作（添加/删除/移动小部件）
        if (Plasmoid.containment.corona.editMode) {
            hoverDialog.visible = false
            return
        }
        collapseTimer.stop()
        hoverDialog.visible = true
        // 显示后下一帧再定位：首次悬停时 widget 尺寸/全局坐标可能未就绪，立即计算会偏移（靠右/向下）
        positionTimer.restart()
    }

    function positionPopup() {
        if (!hoverDialog.visible) {
            return
        }
        // 定位：图标上方居中，紧贴任务栏顶部（不留间隙，避免鼠标穿越时误收起），并 clamp 在屏幕内
        var pos = widget.mapToGlobal(0, 0)
        var dx = pos.x + (widget.width - hoverDialog.width) / 2
        dx = Math.min(Math.max(dx, 4), Screen.width - hoverDialog.width - 4)
        var dy = Math.max(pos.y - hoverDialog.height, 4)
        hoverDialog.x = dx
        hoverDialog.y = dy
    }
    function scheduleCollapse() {
        // 编辑模式下保持收起
        if (Plasmoid.containment.corona.editMode) {
            collapseTimer.stop()
            hoverDialog.visible = false
            return
        }
        collapseTimer.restart()
    }
    function cancelCollapse() {
        collapseTimer.stop()
    }
    // 进入/退出编辑模式时，立即收起悬浮面板
    Connections {
        target: Plasmoid.containment.corona
        function onEditModeChanged() {
            collapseTimer.stop()
            hoverDialog.visible = false
        }
    }
    Timer {
        id: collapseTimer
        interval: 500
        onTriggered: {
            // 收起前兜底检查：鼠标仍在图标或面板上则不收起
            var compactHover = false
            if (widget.compactRepresentation) {
                compactHover = widget.compactRepresentation.hovered
            }
            if (!compactHover && !panelHover.hovered) {
                hoverDialog.visible = false
            }
        }
    }

    // 弹出后下一帧定位（等窗口映射 + widget 尺寸就绪，避免首次悬停位置偏移）
    Timer {
        id: positionTimer
        interval: 0
        onTriggered: widget.positionPopup()
    }

    // 悬浮详情窗口（独立弹窗，位于任务栏图标上方）
    PlasmaCore.Dialog {
        id: hoverDialog
        // 位置由 expandPopup 手动计算（图标上方居中）
        // 悬浮弹出不抢键盘焦点，且置顶
        flags: Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
        // 关键：不抢焦点意味着窗口永远没有激活态，若不关掉“失活即隐藏”，弹窗会在打开的瞬间就被隐藏
        hideOnWindowDeactivate: false
        visible: false
        // 面板高度变化（歌词加载/清除，100↔200）时重新定位，
        // 避免窗口在图标上方锚定后向下扩展盖住任务栏（第一次悬停时歌词未就绪的 bug）
        onHeightChanged: {
            if (visible) {
                widget.positionPopup()
            }
        }

        mainItem: Item {
            width: 280
            height: widget.hasLyrics ? 200 : 100
            // 鼠标在面板任意位置（含按钮上方）→ 保持弹出；移出 → 延迟收起
            // 用 HoverHandler 而不是 MouseArea：按钮会抢走 MouseArea 的 hover，
            // 而 HoverHandler 只是被动观察，鼠标在子控件（按钮）上时依然能感知在面板内
            HoverHandler {
                id: panelHover
                onHoveredChanged: {
                    if (hovered) {
                        widget.cancelCollapse()
                    } else {
                        widget.scheduleCollapse()
                    }
                }
            }
            // 面板空白区域双击 → 呼出正在播放的播放器主窗口（如浏览器播放页）
            // 位于 FullPanel 下层：按钮优先接收点击，空白处由这里处理
            MouseArea {
                id: panelBlankArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onDoubleClicked: widget.raisePlayer()
            }
            FullPanel {
                anchors.fill: parent
                applet: widget
            }
        }
    }

    // 播放中周期性刷新进度（position 是 DBus 属性，不会自动推送）
    Timer {
        interval: 250
        running: widget.playbackStatus === Mpris.PlaybackStatus.Playing
        repeat: true
        onTriggered: {
            widget.updatePosition()
            widget.updateLyrics()
        }
    }

    compactRepresentation: Compact {}

    fullRepresentation: FullPanel { applet: widget }
}
