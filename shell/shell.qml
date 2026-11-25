import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls.Basic
import QtCore

ShellRoot {
    id: root
    property var accounts: []
    property string accountSnapshot: ""
    property var brandIndex: ({})
    property string brandDirectory: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/aether/brand-icons"
    Component.onCompleted: {
        if (!reader.running) reader.running = true
        if (!brandReader.running) brandReader.running = true
    }
    Process {
        id: brandReader
        command: ["cat", root.brandDirectory + "/index.json"]
        stdout: StdioCollector { onStreamFinished: {
            try { root.brandIndex = JSON.parse(text) } catch(e) { root.brandIndex = {} }
        } }
    }
    function brandSource(name) {
        let variant = root.lightTheme ? "light" : "dark"
        let entry = root.brandIndex[name]
        let filename = entry && entry[variant]
        if (filename !== name + "-" + variant + ".png" || !/^[a-z0-9]{1,64}-(dark|light)\.png$/.test(filename)) return ""
        return Qt.resolvedUrl("brand-icons/" + filename)
    }
    property bool opened: false
    property bool pinned: false
    property double now: Date.now()
    property string status: "Waiting for cache"
    property var palette: ({})
    property string schemeMode: "dark"
    property bool themeActive: prefs.followTheme && !!palette.surface && !!palette.onSurface
    property bool lightTheme: themeActive && schemeMode === "light"
    property var installedFonts: Qt.fontFamilies()
    property string sans: installedFonts.indexOf("Inter") >= 0 ? "Inter" : installedFonts.indexOf("Manrope") >= 0 ? "Manrope" : installedFonts.indexOf("Rubik") >= 0 ? "Rubik" : "Noto Sans"
    property string monoFont: installedFonts.indexOf("JetBrains Mono") >= 0 ? "JetBrains Mono" : sans
    property real animatedHeight: naturalHeight
    property real naturalHeight: Math.max(148, Math.min(drawer.height - 12, content.implicitHeight + 44))
    Behavior on animatedHeight { NumberAnimation { duration: 360; easing.type: Easing.InOutCubic } }
    property real reveal: opened ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: Math.round(prefs.motionMs * (root.opened ? 1 : 0.88))
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.42, 0.0, 0.20, 1.0, 1.0, 1.0]
        }
    }
    function smooth(t) { t = Math.max(0, Math.min(1, t)); return t*t*(3-2*t) }
    // Anchor coordinates in the stable overlay: 0 = near edge, 0.5 = centre, 1 = far edge.
    property real ax: prefs.hotspot.indexOf("left") >= 0 ? 0 : prefs.hotspot.indexOf("right") >= 0 ? 1 : 0.5
    property real ay: prefs.hotspot.indexOf("top") >= 0 ? 0 : prefs.hotspot.indexOf("bottom") >= 0 ? 1 : 0.5
    property real panelWidth: Math.max(1, drawer.width - 12)
    property real panelHeight: Math.min(drawer.height - 12, animatedHeight)
    property bool rings: prefs.viewMode === "rings"
    property color sessionColor: tone("primary", "#e8e8e8")
    property color weeklyColor: tone("tertiary", "#9b9b9b")
    function stagger(i) {
        if (!prefs.staggerEnabled) return smooth((reveal - 0.16) / 0.78)
        let delay = 0.14 + Math.min(i, 10) * 0.045
        return smooth((reveal - delay) / (1 - delay))
    }
    function windowFor(account, minutes) {
        let windows = account.windows || []
        return windows.find(w => Number(w.minutes) === minutes) || null
    }
    function remaining(w) {
        return w && w.remaining !== null && w.remaining !== undefined && isFinite(Number(w.remaining)) ? Math.max(0, Math.min(100, Number(w.remaining))) : -1
    }
    property bool settingsOpen: false
    Settings { id: prefs; location: "file:" + (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/aether/preferences.ini"; category: "AetherUI"; property bool followTheme: true; property bool hoverEnabled: true; property int motionMs: 820; property int dismissDelay: 350; property int drawerWidth: 390; property int layoutWidth: 440; property int cacheSeconds: 5; property string viewMode: "grid"; property string hotspot: "top-right"; property bool staggerEnabled: true }
    function loadPalette(text) {
        try { let data = JSON.parse(text); let raw = data.colours || data.colors || data; let p = {}; for (let k in raw) { let v = raw[k]; if (typeof v === "string" && /^#?[0-9a-fA-F]{6}$/.test(v)) { let key = k.replace(/^m3/, ""); key = key.charAt(0).toLowerCase() + key.slice(1); key = key.replace(/[ _-]([a-z])/g, (_, x) => x.toUpperCase()); p[key] = v.startsWith("#") ? v : "#" + v } } root.schemeMode = String(data.mode || "dark").toLowerCase(); root.palette = p } catch(e) { root.palette = {}; root.schemeMode = "dark" }
    }
    property string schemePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/caelestia/scheme.json"
    Process { id: colors; command: ["cat", root.schemePath]; stdout: StdioCollector { onStreamFinished: root.loadPalette(text) } }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!colors.running) colors.running = true }
    function logo(provider) {
        let s = String(provider || "").toLowerCase().replace(/[^a-z0-9]/g, "")
        if (s.includes("codex")) return "codex"
        if (s.includes("claude") || s === "anthropic") return "claude"
        if (s.includes("grok") || s === "xai") return "grok"
        if (s.includes("opencode")) return "opencode"
        if (s === "pi" || s === "piai") return "pi"
        if (s.includes("openrouter")) return "openrouter"
        if (s.includes("deepseek")) return "deepseek"
        if (s.includes("agentrouter")) return "agentrouter"
        if (s.includes("freegg")) return "freegg"
        return /^[a-z0-9]{1,64}$/.test(s) ? s : ""
    }

    function tone(key, fallback) { return (themeActive && palette[key]) || fallback }
    property color surface: tone("surface", "#000000")
    property color cardColor: tone("surfaceContainer", lightTheme ? "#ececec" : "#171717")
    property color buttonColor: tone("primaryContainer", lightTheme ? "#e1e1e1" : "#292929")
    property color outline: tone("outlineVariant", lightTheme ? "#c7c7c7" : "#282828")
    property color track: tone("surfaceContainerHighest", lightTheme ? "#dddddd" : "#333333")
    property color primary: tone("primary", lightTheme ? "#000000" : "#ffffff")
    property color foreground: tone("onSurface", "#ffffff")
    property color muted: tone("onSurfaceVariant", lightTheme ? "#555555" : "#bdbdbd")
    property color iconColor: lightTheme ? "#000000" : "#ffffff"
    component ProviderIcon: Item {
        id: glyph
        property string name: ""
        property string fallback: ""
        // First-party provider marks have their own namespace; never reuse legacy provider SVGs.
        Image {
            id: mono
            anchors.fill: parent
            source: glyph.name === "settings" ? Qt.resolvedUrl("icons/settings" + (root.lightTheme ? "-black.png" : "-white.png")) : glyph.name ? root.brandSource(glyph.name) : ""
            mipmap: true
            smooth: true
            sourceSize.width: 192
            sourceSize.height: 192
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
        }
        Text { anchors.centerIn: parent; text: glyph.fallback; color: root.iconColor; font.family: root.sans; font.pixelSize: 18; visible: mono.status !== Image.Ready }
    }
    component MText: Text { font.family: root.sans; color: root.foreground; font.pixelSize: 14; renderType: Text.QtRendering }
    component MButton: Rectangle {
        id: button
        property string glyph: "settings"
        property string fallback: "⚙"
        signal clicked()
        implicitWidth: 44; implicitHeight: 44
        radius: pointer.pressed ? 14 : pointer.containsMouse ? 16 : 22
        color: pointer.containsMouse ? root.track : root.buttonColor
        Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 150 } }
        ProviderIcon { anchors.centerIn: parent; width: 20; height: 20; name: button.glyph; fallback: button.fallback }
        MouseArea { id: pointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: button.clicked() }
    }
    component MSwitch: Switch {
        id: control
        implicitHeight: 36
        indicator: Rectangle {
            implicitWidth: 48; implicitHeight: 28
            x: control.leftPadding; y: (control.height - height) / 2
            radius: 14; color: control.checked ? root.primary : root.track
            border.width: control.checked ? 0 : 1; border.color: root.outline
            Rectangle {
                width: control.checked ? 20 : 16; height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: control.checked ? parent.width - width - 4 : 6
                color: control.checked ? root.surface : root.muted
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }
    component MSlider: Slider {
        id: control
        implicitWidth: 160; implicitHeight: 32
        background: Rectangle {
            x: control.leftPadding; y: (control.height - height) / 2
            width: control.availableWidth; height: 8; radius: 4; color: root.track
            Rectangle { width: parent.width * control.visualPosition; height: parent.height; radius: 4; color: root.primary }
        }
        handle: Rectangle {
            x: control.leftPadding + control.visualPosition * Math.max(0, control.availableWidth - width)
            y: (control.height - height) / 2
            implicitWidth: 16; implicitHeight: 24; radius: 8; color: root.primary
        }
    }
    property color danger: tone("error", "#ffffff")
    property color onPrimaryContainer: tone("onPrimaryContainer", root.foreground)
    function resetText(ts) {
        if (!ts) return "Reset unknown"
        let seconds = Math.max(0, Math.ceil((ts * 1000 - now) / 1000))
        if (!seconds) return "Reset due"
        let d = Math.floor(seconds / 86400), h = Math.floor(seconds / 3600) % 24, m = Math.floor(seconds / 60) % 60
        return "Resets in " + (d ? d + "d " : "") + (h ? h + "h " : "") + m + "m"
    }
    function show() { closeTimer.stop(); opened = true }
    function hide() { pinned = false; opened = false; closeTimer.stop() }
    Timer { id: closeTimer; interval: prefs.dismissDelay; onTriggered: if (!root.settingsOpen && !root.pinned && !drawerHover.hovered) root.hide() }
    Process {
        id: reader
        command: [Quickshell.env("HOME") + "/.local/bin/aether", "usage"]
        stdout: StdioCollector { onStreamFinished: {
            try { let data = JSON.parse(text); let snapshot = JSON.stringify(data.accounts || []); if (snapshot !== root.accountSnapshot) { root.accountSnapshot = snapshot; root.accounts = data.accounts || [] } root.status = data.updated ? "Updated " + Qt.formatTime(new Date(data.updated * 1000), "HH:mm") : "No cached data" }
            catch(e) { root.status = "Cache unavailable" }
        } }
    }
    Timer { interval: prefs.cacheSeconds * 1000; running: root.opened; repeat: true; triggeredOnStart: true; onTriggered: { root.now = Date.now(); if (!reader.running) reader.running = true } }
    Timer { interval: 1000; running: root.opened; repeat: true; onTriggered: root.now = Date.now() }
    IpcHandler { target: "dashboard"; function settings(): void { root.settingsOpen = !root.settingsOpen; root.hide() } function toggle(): void { if (root.settingsOpen) root.settingsOpen = false; else if (root.opened) root.hide(); else { root.pinned = true; root.show() } } }
    // One stable overlay. The mask is the union of the tiny corner and
    // the final panel footprint; no per-frame Wayland input-mask updates.
    PanelWindow {
        id: drawer
        visible: true
        anchors {
            top: root.ay === 0
            bottom: root.ay === 1
            left: root.ax === 0
            right: root.ax === 1
        }
        implicitWidth: Math.min(prefs.layoutWidth + 12, screen ? screen.width : 452)
        implicitHeight: Math.min(780, screen ? screen.height : 780)
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: corner; Region { item: hitbox } }
        Item {
            id: corner
            x: (parent.width - width) * root.ax
            y: (parent.height - height) * root.ay
            width: prefs.hoverEnabled && !root.settingsOpen ? 18 : 0
            height: width
        }
        Item {
            id: hitbox
            x: (parent.width - width) * root.ax
            y: (parent.height - height) * root.ay
            width: root.opened ? drawer.width : 0
            height: root.opened ? Math.min(drawer.height, Math.max(root.naturalHeight, root.animatedHeight) + 12) : 0
        }
        HoverHandler {
            id: drawerHover
            onHoveredChanged: {
                if (hovered) {
                    closeTimer.stop()
                    if (!root.opened && prefs.hoverEnabled && !root.settingsOpen) root.show()
                } else if (root.opened && !root.pinned) closeTimer.restart()
            }
        }
        Rectangle {
            id: body
            x: 6 + (root.panelWidth - width) * root.ax
            y: 6 + (drawer.height - 12 - height) * root.ay
            width: root.panelWidth * root.reveal
            height: root.panelHeight * root.reveal
            visible: root.reveal > 0.0001
            radius: Math.min(30, width / 2, height / 2)
            color: root.surface
            border.width: 0
            clip: true
            opacity: root.smooth(root.reveal / 0.12)
            // The content is always measured at the FINAL width. No text
            // reflow, scale, or layout resizing during the reveal.
            Flickable {
                id: scroll
                x: 22 + (body.width - root.panelWidth) * root.ax
                y: 22 + (body.height - root.panelHeight) * root.ay
                width: Math.max(1, drawer.width - 56)
                height: Math.max(1, root.panelHeight - 44)
                enabled: root.opened && root.reveal > 0.92
                interactive: enabled && contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width; contentHeight: content.implicitHeight
                clip: true
                ColumnLayout {
                    id: content
                    width: scroll.width; spacing: 16
                    RowLayout {
                        id: heading
                        opacity: root.stagger(0)
                        transform: Translate { y: (1 - heading.opacity) * 12 }
                        Layout.fillWidth: true; spacing: 12
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 4
                            MText { text: "aether.ai"; font.pixelSize: 32; font.weight: Font.DemiBold; font.letterSpacing: -1.3; Layout.fillWidth: true; elide: Text.ElideRight }
                            MText { text: "AI resource monitor"; color: root.muted; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                        MButton { Layout.alignment: Qt.AlignVCenter; onClicked: { root.settingsOpen = true; root.hide() } }
                    }
                    RowLayout {
                        id: sectionHeading
                        opacity: root.stagger(1)
                        transform: Translate { y: (1 - sectionHeading.opacity) * 10 }
                        Layout.fillWidth: true
                        MText { text: "ACCOUNTS · REMAINING QUOTA"; color: root.muted; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.1; Layout.fillWidth: true }
                        MText { text: (root.accounts.length < 10 ? "0" : "") + root.accounts.length; color: root.muted; font.pixelSize: 12; font.family: root.monoFont }
                    }
                    MText { opacity: root.stagger(2); visible: root.accounts.length === 0; text: "No cached accounts. Run aether refresh."; color: root.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Repeater {
                        model: root.rings ? [] : root.accounts
                        delegate: Rectangle {
                            id: accountCard
                            required property var modelData
                            required property int index
                            opacity: root.stagger(index + 2)
                            transform: Translate { y: (1 - accountCard.opacity) * 16 }
                            Layout.fillWidth: true
                            implicitHeight: card.implicitHeight + 36
                            radius: 24; color: root.cardColor
                            ColumnLayout {
                                id: card
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 18
                                spacing: 15
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 12
                                    Rectangle {
                                        Layout.preferredWidth: 44; Layout.preferredHeight: 44
                                        radius: 16; color: root.buttonColor
                                        ProviderIcon { anchors.centerIn: parent; width: 24; height: 24; name: root.logo(accountCard.modelData.provider); fallback: String(accountCard.modelData.provider).slice(0, 1).toUpperCase() }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 3
                                        MText { text: accountCard.modelData.provider; font.weight: Font.DemiBold; font.pixelSize: 17; Layout.fillWidth: true; elide: Text.ElideRight }
                                        MText { text: accountCard.modelData.name; color: root.muted; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                                    }
                                }
                                MText { visible: accountCard.modelData.status !== "ok"; text: accountCard.modelData.status; color: root.danger; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                Repeater {
                                    model: accountCard.modelData.windows || []
                                    delegate: ColumnLayout {
                                        required property var modelData
                                        id: quota
                                        property bool known: modelData.remaining !== null && modelData.remaining !== undefined && isFinite(Number(modelData.remaining))
                                        property real remaining: known ? Math.max(0, Math.min(100, Number(modelData.remaining))) : 0
                                        property color indicator: known && remaining < 20 ? root.danger : root.primary
                                        required property int index
                                        opacity: root.stagger(accountCard.index + 3 + index)
                                        transform: Translate { y: (1 - quota.opacity) * 8 }
                                        Layout.fillWidth: true; spacing: 8
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            MText { text: quota.modelData.minutes === 10080 ? "Weekly" : quota.modelData.minutes === 300 ? "5-hour session" : quota.modelData.minutes ? (quota.modelData.minutes / 60) + "h window" : "Quota"; font.pixelSize: 13; font.weight: Font.Medium; Layout.fillWidth: true }
                                            MText { text: quota.known ? Math.round(quota.remaining) + "%" : "—"; color: quota.indicator; font.family: root.monoFont; font.pixelSize: 19; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignRight }
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true; implicitHeight: 8; radius: 4; color: root.track
                                            Rectangle { width: parent.width * quota.remaining / 100; height: parent.height; radius: Math.min(4, width / 2); color: quota.indicator; Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.InOutCubic } } }
                                        }
                                        MText { text: quota.known ? root.resetText(quota.modelData.reset) : "Quota unavailable"; color: root.muted; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                                    }
                                }
                            }
                        }
                    }
                    GridLayout {
                        visible: root.rings && root.accounts.length > 0
                        Layout.fillWidth: true
                        columns: Math.max(1, Math.min(3, Math.floor((scroll.width + 12) / 156)))
                        columnSpacing: 12; rowSpacing: 12
                        Repeater {
                            model: root.rings ? root.accounts : []
                            delegate: Rectangle {
                                id: ringCard
                                required property var modelData
                                required property int index
                                property var session: root.windowFor(modelData, 300)
                                property var week: root.windowFor(modelData, 10080)
                                property real sessionLeft: root.remaining(session)
                                property real weekLeft: root.remaining(week)
                                Layout.fillWidth: true
                                Layout.minimumWidth: 100
                                Layout.preferredWidth: 144
                                implicitHeight: ringContent.implicitHeight + 24
                                radius: 24; color: root.cardColor
                                opacity: root.stagger(index + 2)
                                transform: Translate { y: (1 - ringCard.opacity) * 16 }
                                ColumnLayout {
                                    id: ringContent
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                    anchors.margins: 12; spacing: 5
                                    Item {
                                        id: ringFace
                                        // Never let the layout independently stretch the two axes.
                                        property real diameter: Math.max(1, Math.min(112, Math.floor(ringCard.width - 24)))
                                        property real strokeSize: 5.5
                                        property real ringRadius: Math.max(1, diameter / 2 - strokeSize / 2 - 2)
                                        // A constant 3px clear gap after rounded caps, on both ends.
                                        property real gapAngle: Math.asin(Math.min(0.95, (strokeSize + 3) / (2 * ringRadius))) * 180 / Math.PI
                                        property real arcSpan: 180 - 2 * gapAngle
                                        property real drawProgress: root.stagger(ringCard.index + 3)
                                        implicitWidth: diameter
                                        implicitHeight: diameter
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.fillWidth: false
                                        Layout.fillHeight: false
                                        Layout.minimumWidth: diameter
                                        Layout.preferredWidth: diameter
                                        Layout.maximumWidth: diameter
                                        Layout.minimumHeight: diameter
                                        Layout.preferredHeight: diameter
                                        Layout.maximumHeight: diameter
                                        Shape {
                                            anchors.fill: parent
                                            preferredRendererType: Shape.CurveRenderer
                                            ShapePath {
                                                fillColor: "transparent"
                                                strokeColor: root.track
                                                strokeWidth: ringFace.strokeSize
                                                capStyle: ShapePath.RoundCap
                                                PathAngleArc {
                                                    centerX: ringFace.diameter / 2; centerY: ringFace.diameter / 2
                                                    radiusX: ringFace.ringRadius; radiusY: ringFace.ringRadius
                                                    startAngle: 270 - ringFace.gapAngle; sweepAngle: -ringFace.arcSpan
                                                }
                                            }
                                            ShapePath {
                                                fillColor: "transparent"
                                                strokeColor: root.track
                                                strokeWidth: ringFace.strokeSize
                                                capStyle: ShapePath.RoundCap
                                                PathAngleArc {
                                                    centerX: ringFace.diameter / 2; centerY: ringFace.diameter / 2
                                                    radiusX: ringFace.ringRadius; radiusY: ringFace.ringRadius
                                                    startAngle: 270 + ringFace.gapAngle; sweepAngle: ringFace.arcSpan
                                                }
                                            }
                                            ShapePath {
                                                fillColor: "transparent"
                                                strokeColor: ringCard.sessionLeft > 0 && ringFace.drawProgress > 0 ? root.sessionColor : "transparent"
                                                strokeWidth: ringFace.strokeSize
                                                capStyle: ShapePath.RoundCap
                                                PathAngleArc {
                                                    centerX: ringFace.diameter / 2; centerY: ringFace.diameter / 2
                                                    radiusX: ringFace.ringRadius; radiusY: ringFace.ringRadius
                                                    startAngle: 270 - ringFace.gapAngle
                                                    sweepAngle: -ringFace.arcSpan * Math.max(0, ringCard.sessionLeft) / 100 * ringFace.drawProgress
                                                }
                                            }
                                            ShapePath {
                                                fillColor: "transparent"
                                                strokeColor: ringCard.weekLeft > 0 && ringFace.drawProgress > 0 ? root.weeklyColor : "transparent"
                                                strokeWidth: ringFace.strokeSize
                                                capStyle: ShapePath.RoundCap
                                                PathAngleArc {
                                                    centerX: ringFace.diameter / 2; centerY: ringFace.diameter / 2
                                                    radiusX: ringFace.ringRadius; radiusY: ringFace.ringRadius
                                                    startAngle: 270 + ringFace.gapAngle
                                                    sweepAngle: ringFace.arcSpan * Math.max(0, ringCard.weekLeft) / 100 * ringFace.drawProgress
                                                }
                                            }
                                        }
                                        ProviderIcon {
                                            anchors.centerIn: parent
                                            width: Math.round(ringFace.diameter * 0.43); height: width
                                            name: root.logo(ringCard.modelData.provider)
                                            fallback: String(ringCard.modelData.provider).slice(0,1).toUpperCase()
                                        }
                                    }
                                    MText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: ringCard.modelData.provider; font.weight: Font.DemiBold; font.pixelSize: 14 }
                                    MText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: ringCard.modelData.name; color: root.muted; font.pixelSize: 11 }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        MText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: root.sessionColor; font.family: root.monoFont; font.pixelSize: 13; text: ringCard.sessionLeft < 0 ? "—" : Math.round(ringCard.sessionLeft) + "%" }
                                        MText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: root.weeklyColor; font.family: root.monoFont; font.pixelSize: 13; text: ringCard.weekLeft < 0 ? "—" : Math.round(ringCard.weekLeft) + "%" }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        MText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: root.muted; font.pixelSize: 10; text: "5h" }
                                        MText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: root.muted; font.pixelSize: 10; text: "Week" }
                                    }
                                    MText { visible: ringCard.modelData.status !== "ok"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: root.danger; font.pixelSize: 11; text: ringCard.modelData.status }
                                    MText { visible: ringCard.session !== null; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; color: root.muted; font.pixelSize: 10; text: "5h · " + root.resetText(ringCard.session ? ringCard.session.reset : null).replace("Resets in ", "") }
                                    MText { visible: ringCard.week !== null; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; color: root.muted; font.pixelSize: 10; text: "W · " + root.resetText(ringCard.week ? ringCard.week.reset : null).replace("Resets in ", "") }
                                }
                            }
                        }
                    }
                    RowLayout {
                        id: footer
                        opacity: root.stagger(Math.min(root.accounts.length + 3, 10))
                        transform: Translate { y: (1 - footer.opacity) * 8 }
                        Layout.fillWidth: true; spacing: 8
                        Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: root.muted }
                        MText { text: "Local cache"; color: root.muted; font.pixelSize: 11 }
                        Item { Layout.fillWidth: true }
                        MText { text: root.status; color: root.muted; font.pixelSize: 11; elide: Text.ElideRight; Layout.maximumWidth: scroll.width * 0.52 }
                    }
                }
            }
        }
    }
    PanelWindow {
        id: settingsPanel
        visible: true
        mask: Region { width: root.settingsOpen ? settingsPanel.width : 0; height: root.settingsOpen ? settingsPanel.height : 0 }
        implicitWidth: Math.min(540, screen ? screen.width - 24 : 540)
        implicitHeight: Math.min(760, screen ? screen.height - 24 : 760)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.settingsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        Rectangle {
            id: settingsBody; anchors.fill: parent; radius: 28; color: root.surface; border.width: 0
            opacity: root.settingsOpen ? 1 : 0; scale: root.settingsOpen ? 1 : 0.92
            Behavior on opacity { NumberAnimation { duration: prefs.motionMs; easing.type: Easing.InOutCubic } }
            Behavior on scale { NumberAnimation { duration: prefs.motionMs; easing.type: Easing.OutCubic } }
            Flickable {
                id: settingsScroll
                anchors.fill: parent; anchors.margins: 24
                clip: true; contentWidth: width; contentHeight: settingsContent.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout { id: settingsContent; width: settingsScroll.width; spacing: 14
                RowLayout { Layout.fillWidth: true
                    MText { text: "Settings"; font.pixelSize: 30; font.letterSpacing: -0.8; font.weight: Font.Medium; color: root.foreground; Layout.fillWidth: true }
                    Rectangle { implicitWidth: 82; implicitHeight: 40; radius: 20; color: root.buttonColor
                        MText { anchors.centerIn: parent; text: "Done"; color: root.foreground; font.weight: Font.Medium }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.settingsOpen = false }
                    }
                }
                MText { text: "Appearance & behaviour"; color: root.muted; font.pixelSize: 14 }
                RowLayout { MText { text: "Follow Caelestia palette"; color: root.foreground; Layout.fillWidth: true } MSwitch { checked: prefs.followTheme; onToggled: prefs.followTheme = checked } }
                RowLayout { MText { text: "Hover activation"; color: root.foreground; Layout.fillWidth: true } MSwitch { checked: prefs.hoverEnabled; onToggled: prefs.hoverEnabled = checked } }
                RowLayout {
                    Layout.fillWidth: true
                    MText { text: "Dashboard layout"; Layout.fillWidth: true }
                    Repeater {
                        model: ["grid", "rings"]
                        delegate: Rectangle {
                            required property string modelData
                            implicitWidth: 82; implicitHeight: 36; radius: 18
                            color: prefs.viewMode === modelData ? root.primary : root.track
                            MText { anchors.centerIn: parent; text: parent.modelData === "grid" ? "Grid" : "Rings"; color: prefs.viewMode === parent.modelData ? root.surface : root.foreground }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: prefs.viewMode = parent.modelData }
                        }
                    }
                }
                MText { text: "Hover position"; font.weight: Font.Medium }
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 132; radius: 20; color: root.cardColor
                    GridLayout {
                        anchors.fill: parent; anchors.margins: 10; columns: 3; rowSpacing: 5; columnSpacing: 5
                        Repeater {
                            model: ["top-left", "top-center", "top-right", "left-center", "", "right-center", "bottom-left", "bottom-center", "bottom-right"]
                            delegate: Rectangle {
                                required property string modelData
                                required property int index
                                Layout.fillWidth: true; Layout.fillHeight: true
                                radius: 10
                                color: modelData === "" ? "transparent" : prefs.hotspot === modelData ? root.primary : root.track
                                MText { anchors.centerIn: parent; text: ["↖","↑","↗","←","SCREEN","→","↙","↓","↘"][parent.index]; color: prefs.hotspot === parent.modelData ? root.surface : root.muted; font.pixelSize: parent.index === 4 ? 10 : 19 }
                                MouseArea { anchors.fill: parent; enabled: parent.modelData !== ""; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: prefs.hotspot = parent.modelData }
                            }
                        }
                    }
                }
                MText { text: prefs.hotspot.replace("-", " "); color: root.muted; font.pixelSize: 12 }
                RowLayout { MText { text: "Stagger content reveal"; Layout.fillWidth: true } MSwitch { checked: prefs.staggerEnabled; onToggled: prefs.staggerEnabled = checked } }
                RowLayout { MText { text: "Animation · " + prefs.motionMs + " ms"; color: root.foreground; Layout.fillWidth: true } MSlider { from: 300; to: 1400; stepSize: 20; value: prefs.motionMs; onMoved: prefs.motionMs = Math.round(value) } }
                RowLayout { MText { text: "Dismiss · " + prefs.dismissDelay + " ms"; color: root.foreground; Layout.fillWidth: true } MSlider { from: 100; to: 1000; stepSize: 50; value: prefs.dismissDelay; onMoved: prefs.dismissDelay = Math.round(value) } }
                RowLayout { MText { text: "Width · " + prefs.layoutWidth + " px"; color: root.foreground; Layout.fillWidth: true } MSlider { from: 360; to: 560; stepSize: 10; value: prefs.layoutWidth; onMoved: prefs.layoutWidth = Math.round(value) } }
                RowLayout { MText { text: "Cache refresh · " + prefs.cacheSeconds + " s"; color: root.foreground; Layout.fillWidth: true } MSlider { from: 2; to: 30; stepSize: 1; value: prefs.cacheSeconds; onMoved: prefs.cacheSeconds = Math.round(value) } }
                MText { text: "Local settings · T3 Code and Caelestia are untouched"; color: root.muted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }
            }
        }
    }

}
