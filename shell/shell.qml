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
    property var allAccounts: []
    property var accounts: allAccounts.filter(a => !hiddenProviders.includes(logo(a.provider)) && !hiddenAccounts.includes(String(a.id)))
    property var hiddenProviders: parseList(prefs.hiddenProviders)
    property var hiddenAccounts: parseList(prefs.hiddenAccounts)
    function parseList(value) { try { let a = JSON.parse(value); return Array.isArray(a) ? a : [] } catch(e) { return [] } }
    function setHidden(key, value, hidden) {
        let list = parseList(prefs[key]).filter(x => x !== value)
        if (hidden) list.push(value)
        prefs[key] = JSON.stringify(list)
    }
    property var providerCatalog: {
        let result = [{id:"codex",name:"Codex"},{id:"claude",name:"Claude Code"},{id:"grok",name:"Grok"},{id:"opencode",name:"OpenCode"},{id:"pi",name:"Pi"},{id:"openrouter",name:"OpenRouter"},{id:"agentrouter",name:"AgentRouter"},{id:"deepseek",name:"DeepSeek"},{id:"freegg",name:"FreeGG"}]
        for (let a of allAccounts) {
            let id = logo(a.provider)
            if (id && !result.some(p => p.id === id)) result.push({id:id,name:a.provider})
        }
        return result
    }
    property var providerGroups: {
        let groups = [
            {name:"First-party agents",note:"Provider-operated coding agents",ids:["codex","claude","grok"]},
            {name:"Harnesses & routing platforms",note:"Agent runtimes and multi-model access",ids:["opencode","pi","openrouter"]},
            {name:"Aggregators",note:"Third-party access providers",ids:["agentrouter","freegg"]},
            {name:"Other providers",note:"Additional model providers and integrations",ids:[]}
        ]
        let assigned = groups[0].ids.concat(groups[1].ids,groups[2].ids), rows = []
        for (let g of groups) {
            let items = providerCatalog.filter(p => g.ids.length ? g.ids.includes(p.id) : !assigned.includes(p.id))
            if (items.length) {
                rows.push({header:true,name:g.name,note:g.note,id:""})
                for (let p of items) rows.push(p)
            }
        }
        return rows
    }
    property string version: "0.2.0"
    property string settingsTab: "Overview"
    property var settingsPages: ["Overview","Appearance","Providers","Analytics","Behaviour","Shortcuts","Updates","About"]
    property var shortcutActions: [
        {id:"toggle",label:"Toggle dashboard",note:"Open or close the quota drawer",mods:"SUPER",key:"U"},
        {id:"settings",label:"Toggle control centre",note:"Open or close settings",mods:"SUPER SHIFT",key:"U"},
        {id:"analytics",label:"Open analytics",note:"Jump directly to quota history",mods:"SUPER ALT",key:"U"},
        {id:"refresh",label:"Refresh local view",note:"Read the existing cache, not the provider API",mods:"Disabled",key:"R"},
        {id:"dismiss",label:"Dismiss aether",note:"Close both surfaces",mods:"Disabled",key:"Escape"}
    ]
    property var shortcutModifiers: ["Disabled","SUPER","SUPER SHIFT","SUPER CTRL","SUPER ALT","SUPER CTRL SHIFT","SUPER CTRL ALT","SUPER SHIFT ALT","CTRL ALT","CTRL SHIFT","ALT SHIFT"]
    property var shortcutKeys: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".split("").concat(["F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12","Escape","space"])
    property var savedBindings: {
        try {
            let v = JSON.parse(prefs.shortcutBindings)
            return v && typeof v === "object" && !Array.isArray(v) ? v : ({})
        } catch(e) { return ({}) }
    }
    function bindingFor(action) {
        let saved = savedBindings[action.id] || {}
        return {mods: shortcutModifiers.includes(saved.mods) ? saved.mods : action.mods, key: shortcutKeys.includes(saved.key) ? saved.key : action.key}
    }
    function setBinding(action, field, value) {
        let next = Object.assign({}, savedBindings)
        let binding = bindingFor(action)
        binding[field] = value
        next[action.id] = binding
        prefs.shortcutBindings = JSON.stringify(next)
    }
    property bool duplicateBindings: {
        let seen = new Set()
        for (let action of shortcutActions) {
            let b = bindingFor(action)
            if (b.mods === "Disabled") continue
            let name = b.mods + "+" + b.key
            if (seen.has(name)) return true
            seen.add(name)
        }
        return false
    }
    property string hyprlandBindings: {
        let lines = []
        if (prefs.globalShortcutsEnabled) {
            for (let action of shortcutActions) {
                let b = bindingFor(action)
                if (b.mods === "Disabled") continue
                let command = "qs -c aether ipc call dashboard " + action.id
                if (prefs.bindSyntax === "lua") lines.push('hl.bind("' + b.mods.split(" ").join(" + ") + ' + ' + b.key + '", hl.dsp.exec_cmd("' + command + '"))')
                else lines.push("bind = " + b.mods + ", " + b.key + ", exec, " + command)
            }
        }
        return lines.join("\n")
    }
    property var activeDropdown: null
    function selectPage(name) {
        if (!settingsPages.includes(name)) return
        if (activeDropdown) activeDropdown.close()
        if (settingsTab !== name && prefs.motionStyle !== "reduced") pageSpring.jump(0)
        settingsTab = name
        if (name === "Updates") runUpdater("status")
        pageScroll.cancelFlick()
        pageScroll.contentY = pageScroll.originY
        // Reset again after the new page layout has had a chance to settle.
        Qt.callLater(function() { if (root.settingsTab === name) pageScroll.contentY = pageScroll.originY })
        if (name === "Analytics") refreshHistory()
    }
    function openSettings(name) {
        hide()
        settingsOpen = true
        if (name) selectPage(name)
    }
    function refreshView() {
        if (!reader.running) reader.running = true
        if (settingsOpen) refreshHistory()
    }
    function dismissAll() { if (activeDropdown) activeDropdown.close(); settingsOpen = false; hide() }
    property var updateInfo: ({message:"No update check yet", installed:"", candidate:""})
    property string updateAction: "status"
    function runUpdater(action) {
        if (updateReader.running) return
        prefs.sync()
        // Installation must survive a live QML reload or closing aether.
        if (action === "apply" || action === "rollback") {
            root.updateInfo = Object.assign({}, root.updateInfo, {message:"Starting " + action + "…", busy:true})
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/aether-update", action, prefs.updateChannel])
            return
        }
        updateAction = action
        updateReader.running = true
    }
    Timer {
        interval: 4000; repeat: true
        running: root.settingsOpen && root.settingsTab === "Updates"
        onTriggered: if (!updateReader.running) root.runUpdater("status")
    }
    Process {
        id: updateReader
        command: [Quickshell.env("HOME") + "/.local/bin/aether-update", root.updateAction, prefs.updateChannel]
        stdout: StdioCollector { onStreamFinished: {
            try { root.updateInfo = JSON.parse(text) }
            catch(e) { root.updateInfo = {message:"Updater unavailable. Run the full installer.", installed:"", candidate:""} }
        } }
    }
    property string analyticsPeriod: "7"
    property string analyticsMetric: "session"
    property var history: []
    property string analyticsStatus: "No recorded history"
    Process {
        id: historyReader
        command: [Quickshell.env("HOME") + "/.local/bin/aether", "history", root.analyticsPeriod]
        stdout: StdioCollector { onStreamFinished: {
            try {
                let data = JSON.parse(text)
                root.history = data.samples || []
                root.analyticsStatus = root.history.length ? "Local quota snapshots · " + root.history.length + " samples" : "No recorded history yet"
            } catch(e) { root.history = []; root.analyticsStatus = "History unavailable; install the updated backend" }
        } }
    }
    function refreshHistory() { if (!historyReader.running) historyReader.running = true }
    onAnalyticsPeriodChanged: refreshHistory()
    onSettingsOpenChanged: if (settingsOpen) { if (prefs.motionStyle !== "reduced") pageSpring.jump(0); if (!reader.running) reader.running = true; refreshHistory(); if (settingsTab === "Updates") runUpdater("status") } else if (activeDropdown) activeDropdown.close()
    Timer { interval: 30000; repeat: true; running: root.settingsOpen; onTriggered: root.refreshHistory() }
    function series() {
        let minutes = analyticsMetric === "weekly" ? 10080 : 300
        return history.filter(a => !hiddenProviders.includes(logo(a.provider)) && !hiddenAccounts.includes(String(a.id)) && Number(a.minutes) === minutes)
    }
    property string accountSnapshot: ""
    property var brandIndex: ({})
    property string brandDirectory: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/aether/brand-icons"
    Component.onCompleted: {
        // Freeze the layer namespace for this instance; changing it live is
        // unsupported by the Wayland layer-shell protocol.
        startupMaterial = requestedMaterial
        if (prefs.motionRevision < 2) {
            if (prefs.motionMs === 820) prefs.motionMs = 1100
            prefs.motionRevision = 2
        }
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
        if (name === "codex") name = "openai"
        if (name === "freegg") name = "agentrouter"
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
    // Mono is the new default. Caelestia is opt-in, as are built-in schemes.
    property var schemeChoices: [
        {id:"mono",name:"Mono",note:"Pure black · white",swatch:["#000000","#ffffff","#9b9b9b"],light:false},
        {id:"mono-light",name:"Mono Light",note:"White · ink",swatch:["#ffffff","#171717","#606060"],light:true},
        {id:"caelestia",name:"Caelestia",note:"Follow the system palette",swatch:[palette.surface || "#202020",palette.primary || "#bcbcbc",palette.tertiary || "#929292"]},
        {id:"midnight",name:"Midnight",note:"Deep navy · ice",swatch:["#0b1220","#9bcaff","#a8b9ff"],light:false,p:{surface:"#0b1220",onSurface:"#edf3ff",surfaceContainer:"#162033",primaryContainer:"#24374f",outlineVariant:"#34455f",surfaceContainerHighest:"#2a3951",primary:"#9bcaff",tertiary:"#a8b9ff",onSurfaceVariant:"#b1c3da",error:"#ffb4ab",onPrimaryContainer:"#e0edff"}},
        {id:"lavender",name:"Lavender",note:"Soft violet · rose",swatch:["#181725","#cbbaff","#f2b7db"],light:false,p:{surface:"#181725",onSurface:"#f3eeff",surfaceContainer:"#25243a",primaryContainer:"#393052",outlineVariant:"#494361",surfaceContainerHighest:"#37344e",primary:"#cbbaff",tertiary:"#f2b7db",onSurfaceVariant:"#c6bddb",error:"#ffb4ab",onPrimaryContainer:"#f1e8ff"}},
        {id:"forest",name:"Forest",note:"Evergreen · sage",swatch:["#0e1b17","#a5d7b7","#d2cb99"],light:false,p:{surface:"#0e1b17",onSurface:"#e4f3e9",surfaceContainer:"#1b2c24",primaryContainer:"#2c4537",outlineVariant:"#3c5445",surfaceContainerHighest:"#304638",primary:"#a5d7b7",tertiary:"#d2cb99",onSurfaceVariant:"#b8cdbf",error:"#ffb4ab",onPrimaryContainer:"#e2f6e8"}},
        {id:"ember",name:"Ember",note:"Charcoal · warm amber",swatch:["#1b1512","#ffc28b","#e8b4a1"],light:false,p:{surface:"#1b1512",onSurface:"#fff0e6",surfaceContainer:"#2b201b",primaryContainer:"#4b3224",outlineVariant:"#614638",surfaceContainerHighest:"#48352b",primary:"#ffc28b",tertiary:"#e8b4a1",onSurfaceVariant:"#d6bfb2",error:"#ffb4ab",onPrimaryContainer:"#ffe6ce"}},
        {id:"paper",name:"Paper",note:"Warm ivory · graphite",swatch:["#f8f5ef","#72523b","#70634c"],light:true,p:{surface:"#f8f5ef",onSurface:"#262019",surfaceContainer:"#eee9df",primaryContainer:"#e7d8c6",outlineVariant:"#cfc4b6",surfaceContainerHighest:"#e1d8cb",primary:"#72523b",tertiary:"#70634c",onSurfaceVariant:"#645b51",error:"#a52d2d",onPrimaryContainer:"#352419"}}
    ]
    property var selectedScheme: schemeChoices.find(x => x.id === prefs.colorScheme) || schemeChoices[0]
    property bool caelestiaRunning: false
    property bool caelestiaAvailable: caelestiaRunning && !!palette.surface && !!palette.onSurface
    property bool themeActive: prefs.colorScheme === "caelestia" && caelestiaAvailable
    property string caelestiaReason: "Install and start Caelestia Shell and generate its colour scheme. Aether requires a running standard caelestia Quickshell instance and a readable palette."
    Process {
        id: caelestiaProbe
        command: ["qs", "-c", "caelestia", "list", "-j"]
        stdout: StdioCollector { onStreamFinished: {
            try { let instances = JSON.parse(text); root.caelestiaRunning = Array.isArray(instances) && instances.some(i => Number(i.pid) > 0) }
            catch(e) { root.caelestiaRunning = false }
        } }
        onExited: (code, status) => { if (code !== 0) root.caelestiaRunning = false }
    }
    Timer {
        interval: 12000; repeat: true; triggeredOnStart: true
        running: root.settingsOpen || prefs.colorScheme === "caelestia"
        onTriggered: if (!caelestiaProbe.running) caelestiaProbe.running = true
    }
    property bool lightTheme: themeActive ? schemeMode === "light" : !!selectedScheme.light
    property var activePalette: themeActive ? palette : selectedScheme.p || ({})
    property color onAccent: tone("onPrimary", lightTheme ? "#ffffff" : "#101010")
    property var installedFonts: Qt.fontFamilies()
    property string sans: prefs.fontChoice !== "auto" && installedFonts.includes(prefs.fontChoice) ? prefs.fontChoice : installedFonts.indexOf("Inter") >= 0 ? "Inter" : installedFonts.indexOf("Manrope") >= 0 ? "Manrope" : installedFonts.indexOf("Rubik") >= 0 ? "Rubik" : "Noto Sans"
    property string monoFont: installedFonts.indexOf("JetBrains Mono") >= 0 ? "JetBrains Mono" : sans
    property real animatedHeight: naturalHeight
    property real naturalHeight: Math.max(148, Math.min(drawer.height - 12, content.implicitHeight + 44))
    Behavior on animatedHeight { NumberAnimation { duration: 360; easing.type: Easing.InOutCubic } }
    // Native counterpart to Modulo's analytic, velocity-preserving spring.
    // FrameAnimation stops at rest; no permanent animation polling.
    component LiquidSpring: Item {
        id: spring
        visible: false; width: 0; height: 0
        property real targetValue: 0
        property real value: 0
        property real velocity: 0
        property real frequency: 16
        property real damping: prefs.motionStyle === "smooth" ? 0.995 : 0.96
        property real tolerance: 0.001
        property bool instant: prefs.motionStyle === "reduced"
        function jump(next) { value = next; velocity = 0 }
        onTargetValueChanged: if (instant) jump(targetValue)
        onInstantChanged: if (instant) jump(targetValue)
        Component.onCompleted: jump(targetValue)
        FrameAnimation {
            running: !spring.instant && (Math.abs(spring.value - spring.targetValue) > spring.tolerance || Math.abs(spring.velocity) > spring.tolerance * 10)
            onTriggered: {
                let dt = Math.min(0.064, Math.max(0, frameTime))
                let f = Math.max(0.1, Math.min(80, spring.frequency))
                let z = Math.max(0.01, Math.min(0.9999, spring.damping))
                let a = f * z, b = f * Math.sqrt(1 - z*z)
                let x = spring.value - spring.targetValue, c = (spring.velocity + a*x) / b
                let decay = Math.exp(-a*dt), co = Math.cos(b*dt), si = Math.sin(b*dt)
                let next = spring.targetValue + decay*(x*co+c*si)
                let speed = decay*((-a*x+b*c)*co+(-a*c-b*x)*si)
                if (Math.abs(next-spring.targetValue) <= spring.tolerance && Math.abs(speed) <= spring.tolerance*10) spring.jump(spring.targetValue)
                else { spring.velocity = speed; spring.value = next }
            }
        }
    }
    function unit(v) { return Math.max(0, Math.min(1, v)) }
    function smooth(t) { t = unit(t); return t*t*(3-2*t) }
    function quintic(t) { t = unit(t); return t*t*t*(t*(t*6-15)+10) }
    property real motionFrequency: (prefs.motionStyle === "smooth" ? 10.5 : 12) * 1100 / Math.max(300, prefs.motionMs)
    LiquidSpring { id: drawerSpring; targetValue: root.opened ? 1 : 0; frequency: root.motionFrequency }
    property real reveal: unit(drawerSpring.value)
    LiquidSpring { id: drawerContentSpring; targetValue: root.opened && root.reveal >= 0.43 ? 1 : 0; frequency: root.motionFrequency * (root.opened ? 1.25 : 1.65); damping: 0.985 }
    LiquidSpring { id: settingsSpring; targetValue: root.settingsOpen ? 1 : 0; frequency: root.motionFrequency * 1.10 }
    property real settingsReveal: unit(settingsSpring.value)
    LiquidSpring { id: settingsContentSpring; targetValue: root.settingsOpen && root.settingsReveal >= 0.55 ? 1 : 0; frequency: root.motionFrequency * (root.settingsOpen ? 1.45 : 1.9); damping: 0.985 }
    LiquidSpring { id: pageSpring; targetValue: root.settingsOpen && root.settingsReveal >= 0.60 ? 1 : 0; frequency: root.motionFrequency * 0.64; damping: 0.995 }
    function heightProgress(p) { return prefs.motionStyle === "liquid" ? unit(p + 0.20*p*(1-p)) : p }
    function pageStage(i) {
        if (prefs.motionStyle === "reduced") return 1
        let delay = prefs.staggerEnabled ? Math.min(i,12)*0.035 : 0
        return quintic((unit(pageSpring.value)-0.16-delay)/(0.84-delay))
    }
    property real finalPanelX: 6 + (drawer.width-12-panelWidth)*ax
    property real finalPanelY: 6 + (drawer.height-12-panelHeight)*ay
    property string requestedMaterial: prefs.materialMode === "legacy" ? (prefs.glassEnabled ? "frosted" : "solid") : prefs.materialMode
    property string startupMaterial: requestedMaterial
    property bool restartForMaterial: (startupMaterial === "liquid") !== (requestedMaterial === "liquid")
    property string effectiveMaterial: restartForMaterial ? startupMaterial : requestedMaterial
    property bool refractionReady: false
    property string refractionStatus: "HyprGlass status not checked"
    property bool glassActive: effectiveMaterial === "frosted" || (effectiveMaterial === "liquid" && refractionReady)
    property bool liquidActive: effectiveMaterial === "liquid" && refractionReady
    property color panelColor: glassActive ? Qt.rgba(surface.r,surface.g,surface.b,(liquidActive ? prefs.liquidTint : prefs.glassOpacity)/100) : surface
    property color materialCard: liquidActive ? Qt.rgba(cardColor.r,cardColor.g,cardColor.b,0.68) : cardColor
    property string liquidConfig: [
        "-- Requires compatible HyprGlass with contour support.",
        "-- Merge into your existing HyprGlass config; do not overwrite it.",
        "if hl.plugin.hyprglass then",
        "    local hg = hl.plugin.hyprglass",
        "    hg.config({ layers = { enabled = true } })",
        "    hg.preset(\"aether-liquid\", {",
        "        blur_strength = 0.65,",
        "        refraction_strength = " + prefs.refractionStrength.toFixed(2) + ",",
        "        chromatic_aberration = " + prefs.glassDispersion.toFixed(2) + ",",
        "        fresnel_strength = 0.65,",
        "        specular_strength = 0.8,",
        "        edge_thickness_px = 20,",
        "        edge_height = " + prefs.glassEdgeHeight + ",",
        "        glass_opacity = 1.0",
        "    })",
        "    hg.layer(\"aether-liquid-drawer\", { preset = \"aether-liquid\", mask_mode = \"contour\", mask_threshold = 0.08, mask_feather = 0.12, live_resample = true })",
        "    hg.layer(\"aether-liquid-settings\", { preset = \"aether-liquid\", mask_mode = \"contour\", mask_threshold = 0.08, mask_feather = 0.12, live_resample = true })",
        "end"
    ].join("\n")
    function checkRefraction() { if (!glassProbe.running) glassProbe.running = true }
    Process {
        id: glassProbe
        onExited: (code, status) => { if (code !== 0) { root.refractionReady = false; root.refractionStatus = "Compatible HyprGlass renderer unavailable" } }
        command: ["hyprctl", "-j", "hyprglass", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let v = JSON.parse(text)
                    let layer = v.features && v.features.layers
                    root.refractionReady = !!(v.active && layer && layer.active && v.shaders !== "failed")
                    root.refractionStatus = root.refractionReady ? "HyprGlass " + v.version + " · layer renderer active" : "HyprGlass not rendering layers" + (layer && layer.reason ? " · "+layer.reason : "")
                } catch(e) {
                    root.refractionReady = false
                    root.refractionStatus = "Compatible HyprGlass renderer unavailable"
                }
            }
        }
    }
    Timer {
        interval: 12000; repeat: true; triggeredOnStart: true
        running: root.settingsOpen || root.requestedMaterial === "liquid" || root.effectiveMaterial === "liquid"
        onTriggered: root.checkRefraction()
    }
    property color glassEdge: Qt.rgba(foreground.r,foreground.g,foreground.b,lightTheme ? 0.16 : 0.23)
    function liquidRadius(w,h,p,finalRadius) {
        let capsule = Math.min(w,h)/2
        if (prefs.motionStyle !== "liquid") return Math.min(finalRadius,capsule)
        let t = quintic((p-0.35)/0.65)
        return Math.min(capsule,capsule*(1-t)+finalRadius*t)
    }
    // Anchor coordinates in the stable overlay: 0 = near edge, 0.5 = centre, 1 = far edge.
    property real ax: prefs.hotspot.indexOf("left") >= 0 ? 0 : prefs.hotspot.indexOf("right") >= 0 ? 1 : 0.5
    property real ay: prefs.hotspot.indexOf("top") >= 0 ? 0 : prefs.hotspot.indexOf("bottom") >= 0 ? 1 : 0.5
    property real panelWidth: Math.max(1, drawer.width - 12)
    property real panelHeight: Math.min(drawer.height - 12, animatedHeight)
    property bool rings: prefs.viewMode === "rings"
    property color sessionColor: tone("primary", lightTheme ? "#222222" : "#e8e8e8")
    property color weeklyColor: tone("tertiary", lightTheme ? "#606060" : "#9b9b9b")
    function stagger(i) {
        if (prefs.motionStyle === "reduced") return reveal
        let p = unit(drawerContentSpring.value)
        let delay = prefs.staggerEnabled ? Math.min(i,10)*0.04 : 0
        return quintic((p-delay)/(1-delay)) * smooth((reveal-0.35)/0.3)
    }
    function windowFor(account, minutes) {
        let windows = account.windows || []
        return windows.find(w => Number(w.minutes) === minutes) || null
    }
    function remaining(w) {
        return w && w.remaining !== null && w.remaining !== undefined && isFinite(Number(w.remaining)) ? Math.max(0, Math.min(100, Number(w.remaining))) : -1
    }
    property bool settingsOpen: false
    Settings { id: prefs; location: "file:" + (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/aether/preferences.ini"; category: "AetherUI"; property bool followTheme: true; property bool hoverEnabled: true; property int motionMs: 1100; property int dismissDelay: 350; property int drawerWidth: 390; property int layoutWidth: 440; property int cacheSeconds: 5; property string viewMode: "grid"; property string hotspot: "top-right"; property bool staggerEnabled: true; property string hiddenProviders: "[]"; property string hiddenAccounts: "[]"; property string chartMode: "line"; property int hotspotSize: 18; property string fontChoice: "auto"; property int cardRadius: 24; property string colorScheme: "mono"; property bool edgeFades: true; property int fadeDepth: 28; property bool localShortcutsEnabled: true; property bool globalShortcutsEnabled: true; property string shortcutBindings: "{}"; property string bindSyntax: "conf"; property string motionStyle: "liquid"; property bool autoUpdate: false; property string updateChannel: "stable"; property int motionRevision: 0; property bool glassEnabled: false; property int glassOpacity: 88; property string materialMode: "legacy"; property int liquidTint: 38; property real refractionStrength: 0.8; property real glassDispersion: 0.35; property int glassEdgeHeight: 28 }
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

    function tone(key, fallback) { return activePalette[key] || fallback }
    property color surface: tone("surface", lightTheme ? "#ffffff" : "#000000")
    property color cardColor: tone("surfaceContainer", lightTheme ? "#ececec" : "#171717")
    property color buttonColor: tone("primaryContainer", lightTheme ? "#e1e1e1" : "#292929")
    property color outline: tone("outlineVariant", lightTheme ? "#c7c7c7" : "#282828")
    property color track: tone("surfaceContainerHighest", lightTheme ? "#dddddd" : "#333333")
    property color primary: tone("primary", lightTheme ? "#000000" : "#ffffff")
    property color foreground: tone("onSurface", lightTheme ? "#171717" : "#ffffff")
    property color muted: tone("onSurfaceVariant", lightTheme ? "#555555" : "#bdbdbd")
    property color iconColor: lightTheme ? "#000000" : "#ffffff"
    component ProviderIcon: Item {
        id: glyph
        property string name: ""
        property string fallback: ""
        // First-party provider marks have their own namespace; never reuse legacy provider SVGs.
        Image {
            id: mono
            anchors.centerIn: parent
            // The upstream Blossom SVG has its own generous clear space. Keep
            // the original artboard; size its image to match other visible marks.
            width: parent.width * ((glyph.name === "codex" || glyph.name === "openai") ? 1.55 : 1)
            height: parent.height * ((glyph.name === "codex" || glyph.name === "openai") ? 1.55 : 1)
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
                id: switchThumb
                LiquidSpring { id: switchSpring; targetValue: control.checked ? 1 : 0; frequency: 20; damping: 0.95 }
                property real slide: root.unit(switchSpring.value)
                width: 16 + 4 * slide; height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: 6 + (parent.width - width - 10) * slide
                color: control.checked ? root.onAccent : root.muted
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
            LiquidSpring { id: sliderSpring; targetValue: control.pressed ? 1.15 : 1; frequency: 22; damping: 0.94 }
            scale: prefs.motionStyle === "liquid" ? sliderSpring.value : 1
        }
    }
    property color danger: tone("error", lightTheme ? "#a52d2d" : "#ffffff")
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
            try { let data = JSON.parse(text); let snapshot = JSON.stringify(data.accounts || []); if (snapshot !== root.accountSnapshot) { root.accountSnapshot = snapshot; root.allAccounts = data.accounts || [] } root.status = data.updated ? "Updated " + Qt.formatTime(new Date(data.updated * 1000), "HH:mm") : "No cached data" }
            catch(e) { root.status = "Cache unavailable" }
        } }
    }
    Timer { interval: prefs.cacheSeconds * 1000; running: root.opened; repeat: true; triggeredOnStart: true; onTriggered: { root.now = Date.now(); if (!reader.running) reader.running = true } }
    Timer { interval: 1000; running: root.opened; repeat: true; onTriggered: root.now = Date.now() }
    IpcHandler {
        target: "dashboard"
        function settings(): void { if (root.settingsOpen) root.dismissAll(); else root.openSettings("") }
        function toggle(): void { if (root.settingsOpen) root.dismissAll(); else if (root.opened) root.hide(); else { root.pinned = true; root.show() } }
        function analytics(): void { root.openSettings("Analytics") }
        function refresh(): void { root.refreshView() }
        function dismiss(): void { root.dismissAll() }
        function shortcuts(): void { root.openSettings("Shortcuts") }
    }
    // Visual-only gradients, attached to the viewport rather than the moving
    // content item. Opacity tracks distance from each end, including short lists.
    component ScrollFade: Item {
        id: edge
        required property Flickable viewport
        property color shade: root.panelColor
        property real depth: Math.min(prefs.fadeDepth, height / 3)
        property real range: Math.max(0, viewport.contentHeight - viewport.height)
        property real distance: Math.max(0, Math.min(range, viewport.contentY - viewport.originY))
        property bool overflowing: prefs.edgeFades && range > 0.5 && depth > 0
        enabled: false
        z: 20
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: edge.depth
            opacity: edge.overflowing ? root.smooth(edge.distance / Math.max(1, edge.depth)) : 0
            visible: opacity > 0
            gradient: Gradient {
                GradientStop { position: 0; color: edge.shade }
                GradientStop { position: 1; color: Qt.rgba(edge.shade.r, edge.shade.g, edge.shade.b, 0) }
            }
        }
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: edge.depth
            opacity: edge.overflowing ? root.smooth((edge.range - edge.distance) / Math.max(1, edge.depth)) : 0
            visible: opacity > 0
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(edge.shade.r, edge.shade.g, edge.shade.b, 0) }
                GradientStop { position: 1; color: edge.shade }
            }
        }
    }
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
        WlrLayershell.namespace: root.startupMaterial === "liquid" ? "aether-liquid-drawer" : "aether-drawer"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: corner; Region { item: hitbox } }
        Item {
            id: corner
            x: (parent.width - width) * root.ax
            y: (parent.height - height) * root.ay
            width: prefs.hoverEnabled && !root.settingsOpen ? prefs.hotspotSize : 0
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
            property real inset: 6 * root.reveal
            property real seed: Math.min(14, root.panelHeight, root.panelWidth)
            x: inset + (drawer.width - 2*inset - width) * root.ax
            y: inset + (drawer.height - 2*inset - height) * root.ay
            width: seed + (root.panelWidth-seed) * root.reveal
            height: seed + (root.panelHeight-seed) * root.heightProgress(root.reveal)
            visible: root.reveal > 0.0001
            radius: root.liquidRadius(width, height, root.reveal, 30)
            color: root.panelColor
            border.width: root.glassActive ? 1 : 0
            border.color: root.glassEdge
            clip: true
            opacity: root.smooth(root.reveal / 0.12)
            // The content is always measured at the FINAL width. No text
            // reflow, scale, or layout resizing during the reveal.
            Flickable {
                id: scroll
                x: root.finalPanelX + 22 - body.x
                y: root.finalPanelY + 22 - body.y
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
                            radius: prefs.cardRadius; color: root.materialCard
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
                                radius: prefs.cardRadius; color: root.materialCard
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
            ScrollFade { anchors.fill: scroll; viewport: scroll }
        }
    }
    component Choice: Rectangle {
        id: choice
        property string label: ""
        property bool githubIcon: false
        property bool selected: false
        property bool elevated: githubIcon
        signal chosen()
        implicitWidth: Math.max(64, choiceText.implicitWidth + 28 + (githubIcon ? 24 : 0))
        implicitHeight: 36
        radius: 18
        color: "transparent"
        LiquidSpring { id: buttonSpring; targetValue: choiceMouse.pressed ? 0.94 : choiceMouse.containsMouse && choice.enabled ? 1.035 : 1; frequency: 22; damping: 0.94 }
        Rectangle {
            anchors.fill: parent; radius: choice.radius
            scale: prefs.motionStyle === "liquid" ? buttonSpring.value : 1
            color: choice.selected ? root.primary : choiceMouse.pressed ? root.buttonColor : choiceMouse.containsMouse ? (choice.elevated ? root.buttonColor : root.track) : choice.elevated ? root.track : root.cardColor
            border.width: choice.elevated && !choice.selected ? 1 : 0
            border.color: choiceMouse.containsMouse ? root.primary : root.outline
            Behavior on color { ColorAnimation { duration: prefs.motionStyle === "reduced" ? 0 : 240 } }
            Behavior on border.color { ColorAnimation { duration: prefs.motionStyle === "reduced" ? 0 : 240 } }
        }
        Row { anchors.centerIn: parent; spacing: 6
            GitHubMark { visible: choice.githubIcon; width: 17; height: 17; anchors.verticalCenter: parent.verticalCenter; ink: choice.selected ? root.onAccent : root.foreground }
            MText { id: choiceText; text: choice.label; color: choice.selected ? root.onAccent : root.foreground; font.pixelSize: 13; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: choiceMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: choice.chosen() }
    }
    component GitHubMark: Item {
        id: githubMark
        implicitWidth: 18; implicitHeight: 18
        property color ink: root.iconColor
        Shape {
            anchors.centerIn: parent; width: 24; height: 24; scale: Math.min(parent.width,parent.height)/24
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1; fillColor: githubMark.ink
                PathSvg { path: "M10.226 17.284c-2.965-.36-5.054-2.493-5.054-5.256 0-1.123.404-2.336 1.078-3.144-.292-.741-.247-2.314.09-2.965.898-.112 2.111.36 2.83 1.01.853-.269 1.752-.404 2.853-.404 1.1 0 1.999.135 2.807.382.696-.629 1.932-1.1 2.83-.988.315.606.36 2.179.067 2.942.72.854 1.101 2 1.101 3.167 0 2.763-2.089 4.852-5.098 5.234.763.494 1.28 1.572 1.28 2.807v2.336c0 .674.561 1.056 1.235.786 4.066-1.55 7.255-5.615 7.255-10.646C23.5 6.188 18.334 1 11.978 1 5.62 1 .5 6.188.5 12.545c0 4.986 3.167 9.12 7.435 10.669.606.225 1.19-.18 1.19-.786V20.63a2.9 2.9 0 0 1-1.078.224c-1.483 0-2.359-.808-2.987-2.313-.247-.607-.517-.966-1.034-1.033-.27-.023-.359-.135-.359-.27 0-.27.45-.471.898-.471.652 0 1.213.404 1.797 1.235.45.651.921.943 1.483.943.561 0 .92-.202 1.437-.719.382-.381.674-.718.944-.943" }
            }
        }
    }
    // Feather FiChevronDown: original 24x24 stroke geometry (MIT).
    component ChevronDown: Item {
        id: chevron
        property color ink: root.foreground
        implicitWidth: 18; implicitHeight: 18
        Shape {
            anchors.centerIn: parent
            width: 24; height: 24
            scale: Math.min(chevron.width,chevron.height)/24
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 2; strokeColor: chevron.ink
                fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M6 9 L12 15 L18 9" }
            }
        }
    }
    component ThemeSwatch: Rectangle {
        id: swatch
        property var colors: ["#000000","#ffffff","#999999"]
        implicitWidth: 42; implicitHeight: 38
        radius: 10; color: colors[0]
        border.width: 1; border.color: Qt.rgba(0.5,0.5,0.5,0.6)
        Row {
            anchors.centerIn: parent; spacing: 3
            Repeater {
                model: swatch.colors.slice(1)
                delegate: Rectangle { required property string modelData; width: 11; height: 23; radius: 5.5; color: modelData }
            }
        }
    }
    component LiquidSelect: ComboBox {
        id: liquidSelect
        property var labelFor: function(value) { return String(value) }
        property bool fontPreview: false
        property bool themeGrid: false
        property bool prominent: false
        property var unavailableReason: function(i) { return "" }
        property bool prefersAbove: {
            // Scroll and resize changes invalidate the mapped position.
            let scrollY = pageScroll.contentY
            let panelH = settingsPanel.height
            let panelW = settingsPanel.width
            let p = mapToItem(null,0,0)
            let desired = Math.min(themeGrid ? 320 : 300,liquidPopup.fullHeight)
            let below = Math.max(0,panelH-p.y-height-14)
            let upper = Math.max(0,p.y-14)
            return below < desired && upper > below
        }
        implicitHeight: 44
        font.family: root.sans
        font.pixelSize: 13
        leftPadding: 14; rightPadding: 40
        hoverEnabled: true
        editable: false
        focusPolicy: Qt.TabFocus
        displayText: currentIndex < 0 ? "Select…" : labelFor(currentText)
        contentItem: MText {
            text: liquidSelect.displayText
            font.family: liquidSelect.fontPreview && root.installedFonts.includes(liquidSelect.currentText) ? liquidSelect.currentText : root.sans
            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            color: liquidSelect.enabled ? root.foreground : root.muted
        }
        background: Rectangle {
            radius: 16
            color: liquidSelect.down ? root.buttonColor : liquidSelect.hovered ? (liquidSelect.prominent ? root.buttonColor : root.track) : liquidSelect.prominent ? root.track : root.cardColor
            border.width: 1
            border.color: liquidSelect.activeFocus || liquidSelect.popup.visible ? root.primary : root.outline
            Behavior on color { ColorAnimation { duration: prefs.motionStyle === "reduced" ? 0 : 220 } }
            Behavior on border.color { ColorAnimation { duration: prefs.motionStyle === "reduced" ? 0 : 220 } }
        }
        indicator: ChevronDown {
            width: 19; height: 19
            x: liquidSelect.width-width-14; y: (liquidSelect.height-height)/2
            ink: liquidSelect.enabled ? root.foreground : root.muted
            rotation: liquidPopup.visible ? (liquidPopup.above ? 0 : 180) : (liquidSelect.prefersAbove ? 180 : 0)
            transformOrigin: Item.Center
            Behavior on rotation { NumberAnimation { duration: prefs.motionStyle === "reduced" ? 0 : 480; easing.type: Easing.InOutCubic } }
        }
        delegate: ItemDelegate {
            id: optionRow
            required property int index
            required property string modelData
            property bool chosen: liquidSelect.currentIndex === index
            property string reason: liquidSelect.unavailableReason(index)
            property bool unavailable: reason.length > 0
            enabled: !unavailable
            property bool over: !unavailable && (hovered || liquidSelect.highlightedIndex === index)
            HoverHandler { id: optionHover }
            ToolTip.visible: optionRow.unavailable && (optionHover.hovered || optionRow.hovered)
            ToolTip.delay: 450
            ToolTip.timeout: 12000
            ToolTip.text: optionRow.reason
            property var scheme: liquidSelect.themeGrid ? root.schemeChoices[index] : null
            hoverEnabled: true
            focusPolicy: Qt.NoFocus
            width: Math.max(1,liquidGrid.cellWidth-6)
            height: liquidGrid.cellHeight-6
            padding: 10
            highlighted: liquidSelect.highlightedIndex === index
            contentItem: RowLayout {
                spacing: 10
                opacity: optionRow.unavailable ? 0.45 : 1
                ThemeSwatch { visible: !!optionRow.scheme; colors: optionRow.scheme ? optionRow.scheme.swatch : ["#000000","#ffffff","#999999"] }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 3
                    MText {
                        Layout.fillWidth: true
                        text: liquidSelect.labelFor(optionRow.modelData)
                        font.family: liquidSelect.fontPreview && root.installedFonts.includes(optionRow.modelData) ? optionRow.modelData : root.sans
                        font.weight: optionRow.chosen ? Font.DemiBold : Font.Normal
                        color: root.foreground; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                    }
                    MText {
                        visible: !!optionRow.scheme; Layout.fillWidth: true
                        text: optionRow.scheme ? optionRow.scheme.note : ""
                        font.pixelSize: 10; color: root.muted; elide: Text.ElideRight
                    }
                }
                MText { visible: optionRow.unavailable || optionRow.chosen; text: optionRow.unavailable ? "!" : "✓"; font.weight: Font.DemiBold; font.pixelSize: 14; color: optionRow.unavailable ? root.muted : root.primary }
            }
            background: Rectangle {
                radius: 14
                color: optionRow.down ? root.buttonColor : optionRow.over ? root.track : optionRow.chosen ? root.buttonColor : liquidSelect.themeGrid ? root.surface : "transparent"
                border.width: optionRow.chosen || optionRow.over ? 1 : 0
                border.color: optionRow.chosen ? root.primary : root.outline
                Behavior on color { ColorAnimation { duration: prefs.motionStyle === "reduced" ? 0 : 180 } }
            }
        }
        popup: Popup {
            id: liquidPopup
            // Keep popups inside the existing layer-shell surface; no native popup window.
            popupType: Popup.Item
            property bool above: false
            property real menuSpaceHeight: Math.max(1,settingsPanel.height-28)
            property int columns: liquidSelect.themeGrid && width >= 340 ? 2 : 1
            property real cell: liquidSelect.themeGrid ? 72 : 44
            property real growth: 0
            property real shownContent: root.quintic((growth-0.24)/0.76)
            property real fullHeight: Math.ceil(liquidSelect.count/columns)*cell+12
            width: liquidSelect.width
            height: Math.max(1,Math.min(liquidSelect.themeGrid ? 320 : 300,fullHeight,menuSpaceHeight))
            y: above ? -height-6 : liquidSelect.height+6
            margins: 8
            padding: 6
            focus: true
            onAboutToShow: {
                if (root.activeDropdown && root.activeDropdown !== liquidPopup) root.activeDropdown.close()
                root.activeDropdown = liquidPopup
                let point = liquidSelect.mapToItem(null,0,0)
                let below = Math.max(0,settingsPanel.height-point.y-liquidSelect.height-14)
                let upper = Math.max(0,point.y-14)
                above = below < Math.min(liquidSelect.themeGrid ? 320 : 300,fullHeight) && upper > below
                menuSpaceHeight = above ? upper : below
            }
            onClosed: if (root.activeDropdown === liquidPopup) root.activeDropdown = null
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            background: Item {
                Rectangle {
                    x: 0
                    y: liquidPopup.above ? parent.height-height : 0
                    width: Math.max(1,parent.width*liquidPopup.growth)
                    height: Math.max(1,parent.height*root.heightProgress(liquidPopup.growth))
                    radius: root.liquidRadius(width,height,liquidPopup.growth,20)
                    opacity: root.smooth(liquidPopup.growth/0.14)
                    color: root.cardColor; border.width: 1; border.color: root.outline
                }
            }
            contentItem: Item {
                id: dropdownContent
                Item {
                    x: 0
                    y: liquidPopup.above ? parent.height-height : 0
                    width: parent.width*liquidPopup.growth
                    height: parent.height*root.heightProgress(liquidPopup.growth)
                    clip: true
                    GridView {
                        id: liquidGrid
                        // Keep content at its final coordinates during clipping.
                        x: -parent.x; y: -parent.y
                        width: dropdownContent.width; height: dropdownContent.height
                        clip: true
                        opacity: liquidPopup.shownContent
                        // Do not toggle focus eligibility during the animation.
                        model: liquidSelect.delegateModel
                        currentIndex: liquidSelect.highlightedIndex
                        cellWidth: width/liquidPopup.columns
                        cellHeight: liquidPopup.cell
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                }
            }
            enter: Transition {
                NumberAnimation { target: liquidPopup; property: "growth"; to: 1; duration: prefs.motionStyle === "reduced" ? 0 : Math.round(prefs.motionMs*(prefs.motionStyle === "smooth" ? 0.88 : 0.78)); easing.type: Easing.InOutCubic }
            }
            exit: Transition {
                NumberAnimation { target: liquidPopup; property: "growth"; to: 0; duration: prefs.motionStyle === "reduced" ? 0 : Math.round(prefs.motionMs*0.58); easing.type: Easing.InOutCubic }
            }
        }
    }
    component SectionTitle: MText { font.pixelSize: 18; font.weight: Font.DemiBold; Layout.fillWidth: true }
    component Description: MText { font.pixelSize: 13; color: root.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    component StatCard: Rectangle {
        id: stat
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        implicitHeight: 100
        radius: 20; color: root.materialCard
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 16; spacing: 6
            Description { text: stat.label }
            MText { text: stat.value; font.pixelSize: 29; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
            Item { Layout.fillHeight: true }
        }
    }
    component LinkRow: Rectangle {
        id: link
        property string label: ""
        property string url: ""
        property bool githubIcon: false
        Layout.fillWidth: true; implicitHeight: 48; radius: 14
        color: linkMouse.pressed ? root.buttonColor : linkMouse.containsMouse ? (link.githubIcon ? root.buttonColor : root.track) : link.githubIcon ? root.track : root.cardColor
        border.width: link.githubIcon ? 1 : 0; border.color: linkMouse.containsMouse ? root.primary : root.outline
        Behavior on color { ColorAnimation { duration: prefs.motionStyle === "reduced" ? 0 : 240 } }
        RowLayout { anchors.fill: parent; anchors.margins: 14
            GitHubMark { visible: link.githubIcon; Layout.preferredWidth: 18; Layout.preferredHeight: 18; ink: root.foreground }
            MText { text: link.label; Layout.fillWidth: true; font.weight: Font.Medium }
            MText { text: "↗"; color: root.muted }
        }
        MouseArea { id: linkMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(link.url) }
    }
    PanelWindow {
        id: settingsPanel
        visible: true
        mask: Region { width: root.settingsOpen ? settingsPanel.width : 0; height: root.settingsOpen ? settingsPanel.height : 0 }
        implicitWidth: Math.max(320, Math.min(1000, screen ? screen.width - 32 : 1000))
        implicitHeight: Math.max(300, Math.min(720, screen ? screen.height - 32 : 720))
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: root.startupMaterial === "liquid" ? "aether-liquid-settings" : "aether-settings"
        WlrLayershell.keyboardFocus: root.settingsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        Rectangle {
            id: settingsBody
            anchors.centerIn: parent
            width: settingsPanel.width * root.settingsReveal
            height: settingsPanel.height * root.heightProgress(root.settingsReveal)
            radius: root.liquidRadius(width, height, root.settingsReveal, 30); color: root.panelColor
            border.width: root.glassActive ? 1 : 0; border.color: root.glassEdge
            clip: true
            opacity: root.smooth(root.settingsReveal/0.1)
            visible: root.settingsReveal > 0.0001
            // Local shortcuts are active only when the settings window has focus.
            Shortcut { sequence: "Escape"; context: Qt.WindowShortcut; enabled: root.settingsOpen && prefs.localShortcutsEnabled; autoRepeat: false; onActivated: root.dismissAll() }
            Shortcut { sequence: "Ctrl+1"; context: Qt.WindowShortcut; enabled: root.settingsOpen && prefs.localShortcutsEnabled; autoRepeat: false; onActivated: root.selectPage("Overview") }
            Shortcut { sequence: "Ctrl+2"; context: Qt.WindowShortcut; enabled: root.settingsOpen && prefs.localShortcutsEnabled; autoRepeat: false; onActivated: root.selectPage("Appearance") }
            Shortcut { sequence: "Ctrl+3"; context: Qt.WindowShortcut; enabled: root.settingsOpen && prefs.localShortcutsEnabled; autoRepeat: false; onActivated: root.selectPage("Providers") }
            Shortcut { sequence: "Ctrl+4"; context: Qt.WindowShortcut; enabled: root.settingsOpen && prefs.localShortcutsEnabled; autoRepeat: false; onActivated: root.selectPage("Analytics") }
            Shortcut { sequence: "Ctrl+5"; context: Qt.WindowShortcut; enabled: root.settingsOpen && prefs.localShortcutsEnabled; autoRepeat: false; onActivated: root.selectPage("Behaviour") }
            Shortcut { sequence: "Ctrl+6"; context: Qt.WindowShortcut; enabled: root.settingsOpen && prefs.localShortcutsEnabled; autoRepeat: false; onActivated: root.selectPage("Shortcuts") }
            Shortcut { sequence: "Ctrl+7"; context: Qt.WindowShortcut; enabled: root.settingsOpen && prefs.localShortcutsEnabled; autoRepeat: false; onActivated: root.selectPage("Updates") }
            Shortcut { sequence: "Ctrl+8"; context: Qt.WindowShortcut; enabled: root.settingsOpen && prefs.localShortcutsEnabled; autoRepeat: false; onActivated: root.selectPage("About") }
            Shortcut { sequence: "Ctrl+R"; context: Qt.WindowShortcut; enabled: root.settingsOpen && prefs.localShortcutsEnabled; autoRepeat: false; onActivated: root.refreshView() }
            RowLayout {
                anchors.centerIn: parent
                width: Math.max(1,settingsPanel.width-24); height: Math.max(1,settingsPanel.height-24)
                opacity: root.quintic(settingsContentSpring.value)
                enabled: root.settingsOpen && opacity > 0.85
                spacing: 0
                Rectangle {
                    Layout.preferredWidth: settingsPanel.width < 680 ? 126 : 216
                    Layout.fillHeight: true
                    color: root.materialCard; radius: 24
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; spacing: 8
                        MText { text: "aether.ai"; font.pixelSize: settingsPanel.width < 680 ? 20 : 26; font.weight: Font.DemiBold; font.letterSpacing: -0.9; Layout.fillWidth: true }
                        Description { text: "Control centre"; font.pixelSize: 11 }
                        Item { Layout.preferredHeight: 12 }
                        Item {
                            id: navigationTrack
                            property real rowHeight: Math.max(28, Math.min(44, (settingsPanel.height-190)/root.settingsPages.length-8))
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.settingsPages.length * (rowHeight+8)-8
                            LiquidSpring { id: navSpring; targetValue: Math.max(0,root.settingsPages.indexOf(root.settingsTab))*(navigationTrack.rowHeight+8); frequency: 18; damping: 0.9; tolerance: 0.05 }
                            Rectangle {
                                width: parent.width; height: navigationTrack.rowHeight; radius: height/2
                                y: Math.max(0,Math.min(parent.height-height,navSpring.value))
                                color: root.primary
                            }
                            Column {
                                anchors.fill: parent; spacing: 8
                                Repeater {
                                    model: root.settingsPages
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: navigationTrack.width; height: navigationTrack.rowHeight; radius: height/2
                                        color: root.settingsTab !== modelData && navMouse.containsMouse ? root.track : "transparent"
                                        MText { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData; color: root.settingsTab === parent.modelData ? root.onAccent : root.foreground; font.weight: Font.Medium; font.pixelSize: 13 }
                                        MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectPage(parent.modelData) }
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                        Description { text: "MIT · v" + root.version; font.pixelSize: 11 }
                        Choice { label: "GitHub ↗"; githubIcon: true; Layout.fillWidth: true; onChosen: Qt.openUrlExternally("https://github.com/maynkudu/aether-ai") }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 18; spacing: 16
                    RowLayout {
                        Layout.fillWidth: true
                        Item {
                            id: pageHeading
                            Layout.fillWidth: true; implicitHeight: headingLabel.implicitHeight
                            Item {
                                anchors.left: parent.left; anchors.top: parent.top
                                height: parent.height; width: parent.width*root.quintic(root.unit(pageSpring.value)/0.55)
                                clip: true
                                MText { id: headingLabel; text: root.settingsTab; width: pageHeading.width; font.pixelSize: 31; font.weight: Font.DemiBold; font.letterSpacing: -1; elide: Text.ElideRight }
                            }
                        }
                        Choice { label: "Done"; onChosen: root.settingsOpen = false }
                    }
                    Item {
                        id: pageViewport
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Item {
                            id: pageRevealClip
                            anchors.left: parent.left; anchors.top: parent.top
                            width: parent.width*root.quintic((root.unit(pageSpring.value)-0.15)/0.85)
                            height: parent.height; clip: true
                        Flickable {
                        id: pageScroll
                        width: pageViewport.width; height: pageViewport.height
                        clip: true; contentWidth: width; contentHeight: page.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        ColumnLayout {
                            id: page
                            width: pageScroll.width; spacing: 16
                            opacity: root.pageStage(0)
                            ColumnLayout {
                                visible: root.settingsTab === "Overview"; Layout.fillWidth: true; spacing: 14
                                Description { opacity: root.pageStage(1); transform: Translate { x: -18*(1-root.pageStage(1)); y: -5*(1-root.pageStage(1)) }
                                    text: "Your AI resources, in one place. All data stays on this device." }
                                GridLayout { opacity: root.pageStage(2); transform: Translate { x: -18*(1-root.pageStage(2)); y: -5*(1-root.pageStage(2)) }
                                    
                                    columns: 2; Layout.fillWidth: true; columnSpacing: 12; rowSpacing: 12
                                    StatCard { label: "Visible accounts"; value: String(root.accounts.length) }
                                    StatCard { label: "Healthy accounts"; value: String(root.accounts.filter(a => a.status === "ok").length) }
                                    StatCard { label: "Providers"; value: String(new Set(root.accounts.map(a => a.provider)).size) }
                                    StatCard { label: "Quota history"; value: String(root.history.length) }
                                }
                                SectionTitle { opacity: root.pageStage(3); transform: Translate { x: -18*(1-root.pageStage(3)); y: -5*(1-root.pageStage(3)) }
                                    text: "Current limits" }
                                Description { opacity: root.pageStage(4); transform: Translate { x: -18*(1-root.pageStage(4)); y: -5*(1-root.pageStage(4)) }
                                    text: root.status }
                                Repeater {
                                    model: root.accounts
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        opacity: root.pageStage(index+5)
                                        transform: Translate { x: -18*(1-root.pageStage(index+5)); y: -5*(1-root.pageStage(index+5)) }
                                        id: overviewAccount
                                        Layout.fillWidth: true; implicitHeight: overviewDetails.implicitHeight+28; radius: 18; color: root.materialCard
                                        ColumnLayout {
                                            id: overviewDetails
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14; spacing: 12
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 12
                                                ProviderIcon { Layout.preferredWidth: 32; Layout.preferredHeight: 32; name: root.logo(overviewAccount.modelData.provider); fallback: String(overviewAccount.modelData.provider).slice(0,1).toUpperCase() }
                                                ColumnLayout { Layout.fillWidth: true; spacing: 3
                                                    MText { text: overviewAccount.modelData.provider + " · " + overviewAccount.modelData.name; Layout.fillWidth: true; elide: Text.ElideRight; font.weight: Font.Medium }
                                                    Description { text: overviewAccount.modelData.status; font.pixelSize: 11 }
                                                }
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 18
                                                Repeater {
                                                    model: [{label:"Session",value:root.remaining(root.windowFor(overviewAccount.modelData,300)),tint:root.sessionColor},{label:"Weekly",value:root.remaining(root.windowFor(overviewAccount.modelData,10080)),tint:root.weeklyColor}]
                                                    delegate: ColumnLayout {
                                                        id: overviewQuota
                                                        required property var modelData
                                                        required property int index
                                                        Layout.fillWidth: true; spacing: 6
                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            MText { text: overviewQuota.modelData.label; color: root.muted; font.pixelSize: 11; Layout.fillWidth: true }
                                                            MText { text: overviewQuota.modelData.value < 0 ? "—" : Math.round(overviewQuota.modelData.value)+"%"; font.family: root.monoFont; font.pixelSize: 12 }
                                                        }
                                                        Rectangle {
                                                            Layout.fillWidth: true; implicitHeight: 5; radius: 3; color: root.track
                                                            Rectangle { width: parent.width*Math.max(0,overviewQuota.modelData.value)/100*root.pageStage(overviewAccount.index+7+overviewQuota.index); height: parent.height; radius: 3; color: overviewQuota.modelData.tint }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                Description { opacity: root.pageStage(5); transform: Translate { x: -18*(1-root.pageStage(5)); y: -5*(1-root.pageStage(5)) }
                                    visible: root.accounts.length === 0; text: "No visible accounts. Check provider preferences or run aether refresh." }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Appearance"; Layout.fillWidth: true; spacing: 14
                                SectionTitle { opacity: root.pageStage(1); transform: Translate { x: -18*(1-root.pageStage(1)); y: -5*(1-root.pageStage(1)) }
                                    text: "Dashboard" }
                                RowLayout { opacity: root.pageStage(2); transform: Translate { x: -18*(1-root.pageStage(2)); y: -5*(1-root.pageStage(2)) }
                                    Layout.fillWidth: true
                                    MText { text: "Layout"; Layout.fillWidth: true }
                                    LiquidSelect { Layout.preferredWidth: 180; model: ["Grid","Rings"]; currentIndex: prefs.viewMode === "rings" ? 1 : 0; onActivated: prefs.viewMode = index === 1 ? "rings" : "grid" }
                                }
                                SectionTitle { opacity: root.pageStage(3); transform: Translate { x: -18*(1-root.pageStage(3)); y: -5*(1-root.pageStage(3)) }
                                    text: "Colour scheme" }
                                Description { opacity: root.pageStage(4); transform: Translate { x: -18*(1-root.pageStage(4)); y: -5*(1-root.pageStage(4)) }
                                    text: "Choose a built-in palette or follow Caelestia. Mono is the default." }
                                RowLayout { opacity: root.pageStage(5); transform: Translate { x: -18*(1-root.pageStage(5)); y: -5*(1-root.pageStage(5)) }
                                    
                                    Layout.fillWidth: true; spacing: 12
                                    Rectangle {
                                        Layout.preferredWidth: 54; Layout.preferredHeight: 42; radius: 12; color: root.selectedScheme.swatch[0]
                                        border.width: 1; border.color: root.outline
                                        Row {
                                            anchors.centerIn: parent; spacing: 4
                                            Repeater { model: root.selectedScheme.swatch.slice(1); delegate: Rectangle { required property string modelData; width: 14; height: 24; radius: 7; color: modelData } }
                                        }
                                    }
                                    LiquidSelect {
                                        Layout.fillWidth: true
                                        id: schemeSelector
                                        themeGrid: true
                                        unavailableReason: function(i) { return root.schemeChoices[i] && root.schemeChoices[i].id === "caelestia" && !root.caelestiaAvailable ? root.caelestiaReason : "" }
                                        model: root.schemeChoices.map(x => x.name)
                                        currentIndex: Math.max(0,root.schemeChoices.findIndex(x => x.id === prefs.colorScheme))
                                        onActivated: { if (unavailableReason(index)) { currentIndex = Math.max(0,root.schemeChoices.findIndex(x => x.id === prefs.colorScheme)); return } prefs.colorScheme = root.schemeChoices[index].id }
                                    }
                                }
                                Description { opacity: root.pageStage(6); transform: Translate { x: -18*(1-root.pageStage(6)); y: -5*(1-root.pageStage(6)) }
                                    visible: !root.caelestiaAvailable; text: prefs.colorScheme === "caelestia" ? "Caelestia unavailable · using Mono. " + root.caelestiaReason : "Caelestia unavailable · requires a running shell and palette." }
                                RowLayout { opacity: root.pageStage(7); transform: Translate { x: -18*(1-root.pageStage(7)); y: -5*(1-root.pageStage(7)) }
                                    MText { text: "Drawer width · " + prefs.layoutWidth + " px"; Layout.fillWidth: true } MSlider { from: 360; to: 560; stepSize: 10; value: prefs.layoutWidth; onMoved: prefs.layoutWidth = Math.round(value) } }
                                RowLayout { opacity: root.pageStage(8); transform: Translate { x: -18*(1-root.pageStage(8)); y: -5*(1-root.pageStage(8)) }
                                    MText { text: "Card rounding · " + prefs.cardRadius + " px"; Layout.fillWidth: true } MSlider { from: 8; to: 32; stepSize: 2; value: prefs.cardRadius; onMoved: prefs.cardRadius = Math.round(value) } }
                                SectionTitle { opacity: root.pageStage(9); text: "Surface material" }
                                RowLayout {
                                    opacity: root.pageStage(10); Layout.fillWidth: true
                                    MText { text: "Material"; Layout.fillWidth: true }
                                    LiquidSelect {
                                        Layout.preferredWidth: 200
                                        unavailableReason: function(i) { return i === 2 && !root.refractionReady ? "Requires Hyprland and a compatible HyprGlass plugin with its layer renderer enabled. Install the plugin, enable layers, then check renderer below." : "" }
                                        model: ["Solid","Frosted Glass","Liquid Glass"]
                                        currentIndex: Math.max(0,["solid","frosted","liquid"].indexOf(root.requestedMaterial))
                                        onActivated: { if (unavailableReason(index)) { currentIndex = Math.max(0,["solid","frosted","liquid"].indexOf(root.requestedMaterial)); return } prefs.materialMode = ["solid","frosted","liquid"][index]; if(index === 2) root.checkRefraction() }
                                    }
                                }
                                ColumnLayout {
                                    visible: !root.refractionReady && root.requestedMaterial !== "liquid"
                                    Layout.fillWidth: true; spacing: 8; opacity: root.pageStage(11)
                                    Description { text: "Liquid Glass unavailable · " + root.refractionStatus + ". Install a compatible HyprGlass plugin and enable its layer renderer." }
                                    Choice { label: "Check renderer"; enabled: !glassProbe.running; onChosen: root.checkRefraction() }
                                    LinkRow { label: "HyprGlass setup & compatibility"; url: "https://github.com/hyprnux/hyprglass" }
                                    // The user must be able to enable the layer renderer
                                    // before the material itself becomes selectable.
                                    TextArea {
                                        id: prerequisitePreset
                                        Layout.fillWidth: true; Layout.preferredHeight: Math.min(160,Math.max(80,contentHeight+24))
                                        text: root.liquidConfig; readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere
                                        focusPolicy: Qt.NoFocus; activeFocusOnPress: false
                                        color: root.foreground; font.family: root.monoFont; font.pixelSize: 11; padding: 12
                                        background: Rectangle { radius: 16; color: root.cardColor; border.width: 1; border.color: root.outline }
                                    }
                                    Choice { label: "Copy setup Lua"; elevated: true; onChosen: { prerequisitePreset.selectAll(); prerequisitePreset.copy() } }
                                }
                                RowLayout {
                                    visible: root.requestedMaterial === "frosted"; opacity: root.pageStage(11)
                                    MText { text: "Frosted opacity · " + prefs.glassOpacity + "%"; Layout.fillWidth: true }
                                    MSlider { from: 70; to: 98; stepSize: 2; value: prefs.glassOpacity; onMoved: prefs.glassOpacity = Math.round(value) }
                                }
                                ColumnLayout {
                                    visible: root.requestedMaterial === "liquid"; Layout.fillWidth: true; spacing: 10
                                    opacity: root.pageStage(12)
                                    Description { text: "Real desktop refraction through HyprGlass. The compositor samples the windows and wallpaper behind aether and bends that image around the animated glass contour." }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        MText { text: "Liquid tint · " + prefs.liquidTint + "%"; Layout.fillWidth: true }
                                        MSlider { from: 20; to: 75; stepSize: 1; value: prefs.liquidTint; onMoved: prefs.liquidTint = Math.round(value) }
                                    }
                                    SectionTitle { text: "Optical preset" }
                                    Description { text: "These controls update the Lua preset below. Copy the preset into HyprGlass and reload your compositor config to apply them." }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        MText { text: "Refraction · " + prefs.refractionStrength.toFixed(2); Layout.fillWidth: true }
                                        MSlider { from: 0; to: 1; stepSize: 0.05; value: prefs.refractionStrength; onMoved: prefs.refractionStrength = value }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        MText { text: "Chromatic dispersion · " + prefs.glassDispersion.toFixed(2); Layout.fillWidth: true }
                                        MSlider { from: 0; to: 1; stepSize: 0.05; value: prefs.glassDispersion; onMoved: prefs.glassDispersion = value }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        MText { text: "Lens height · " + prefs.glassEdgeHeight + " px"; Layout.fillWidth: true }
                                        MSlider { from: 0; to: 40; stepSize: 2; value: prefs.glassEdgeHeight; onMoved: prefs.glassEdgeHeight = Math.round(value) }
                                    }
                                    Description { color: root.refractionReady ? root.muted : root.danger; text: root.refractionStatus }
                                    Description { text: "Requires a version-matched HyprGlass plugin and the aether layer preset. Until its layer renderer is active, aether uses Solid. Renderer status does not verify that the namespaces were whitelisted." }
                                    Choice { label: "Check renderer"; enabled: !glassProbe.running; onChosen: root.checkRefraction() }
                                    LinkRow { label: "HyprGlass installation & compatibility"; url: "https://github.com/hyprnux/hyprglass" }
                                    TextArea {
                                        id: glassConfigText
                                        Layout.fillWidth: true; Layout.preferredHeight: Math.max(100,contentHeight+24)
                                        text: root.liquidConfig; readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere
                                        focusPolicy: Qt.NoFocus; activeFocusOnPress: false
                                        color: root.foreground; selectionColor: root.primary; selectedTextColor: root.onAccent
                                        font.family: root.monoFont; font.pixelSize: 11; padding: 12
                                        background: Rectangle { radius: 16; color: root.cardColor; border.width: 1; border.color: root.outline }
                                    }
                                    Choice { label: "Copy HyprGlass Lua"; elevated: true; onChosen: { glassConfigText.selectAll(); glassConfigText.copy() } }
                                    Description { text: "Merge the snippet with your existing plugin configuration. Aether does not install compositor plugins or change global rules. Check hyprctl layers and adjust names if your compositor reports different namespaces." }
                                }
                                Description {
                                    visible: root.requestedMaterial === "frosted"; opacity: root.pageStage(12)
                                    text: "Traditional translucency and compositor blur. Use your normal Hyprland blur rules for aether-drawer and aether-settings."
                                }
                                Description {
                                    visible: root.restartForMaterial; opacity: root.pageStage(12); color: root.primary
                                    text: "Restart aether to switch into or out of Liquid Glass. Wayland layer namespaces cannot change after the window connects."
                                }
                                SectionTitle { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    text: "Typography" }
                                Description { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    text: "Choose the UI typeface. The dropdown lists installed families and the preview updates immediately." }
                                Rectangle { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    
                                    Layout.fillWidth: true; implicitHeight: 94; radius: 20; color: root.materialCard
                                    ColumnLayout { anchors.fill: parent; anchors.margins: 16; spacing: 4
                                        MText { text: "Intelligence, within limits."; font.pixelSize: 24; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                        Description { text: root.sans + " · Aa Bb Cc 0123456789"; font.pixelSize: 12 }
                                    }
                                }
                                LiquidSelect { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    
                                    id: fontSelector
                                    Layout.fillWidth: true; fontPreview: true
                                    model: ["auto","Inter","Manrope","Montserrat","Poppins","DM Sans","Plus Jakarta Sans","Space Grotesk","Outfit","Sora","Figtree","Rubik","Noto Sans"].filter(n => n === "auto" || root.installedFonts.includes(n))
                                    labelFor: function(n) { return n === "auto" ? "Automatic" : n }
                                    currentIndex: Math.max(0,model.indexOf(prefs.fontChoice))
                                    onActivated: prefs.fontChoice = model[index]
                                }
                                Description { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    text: "Install the curated font pack with bash install.sh --ui-only --fetch-fonts from the repository, then restart aether." }
                                SectionTitle { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    text: "Scrolling" }
                                RowLayout { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    MText { text: "Scroll edge fades"; Layout.fillWidth: true } MSwitch { checked: prefs.edgeFades; onToggled: prefs.edgeFades = checked } }
                                RowLayout { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    MText { text: "Fade depth · " + prefs.fadeDepth + " px"; Layout.fillWidth: true } MSlider { enabled: prefs.edgeFades; from: 12; to: 48; stepSize: 2; value: prefs.fadeDepth; onMoved: prefs.fadeDepth = Math.round(value) } }
                                SectionTitle { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    text: "Motion" }
                                Description { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    text: "Liquid uses Modulo-inspired interruptible springs and capsule-shaped surfaces. Smooth is more restrained. Reduced disables these transitions." }
                                RowLayout { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    
                                    Layout.fillWidth: true
                                    MText { text: "Motion style"; Layout.fillWidth: true }
                                    LiquidSelect { Layout.preferredWidth: 180; model: ["Liquid","Smooth","Reduced"]; currentIndex: Math.max(0,["liquid","smooth","reduced"].indexOf(prefs.motionStyle)); onActivated: prefs.motionStyle = ["liquid","smooth","reduced"][index] }
                                }
                                RowLayout { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    MText { text: "Stagger content reveal"; Layout.fillWidth: true } MSwitch { checked: prefs.staggerEnabled; onToggled: prefs.staggerEnabled = checked } }
                                RowLayout { opacity: root.pageStage(12); transform: Translate { x: -18*(1-root.pageStage(12)); y: -5*(1-root.pageStage(12)) }
                                    MText { text: "Animation · " + prefs.motionMs + " ms"; Layout.fillWidth: true } MSlider { from: 300; to: 1800; stepSize: 20; value: prefs.motionMs; onMoved: prefs.motionMs = Math.round(value) } }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Providers"; Layout.fillWidth: true; spacing: 12
                                Description { opacity: root.pageStage(1); transform: Translate { x: -18*(1-root.pageStage(1)); y: -5*(1-root.pageStage(1)) }
                                    text: "Choose which providers and accounts appear in aether. These switches control visibility only; they do not disable accounts in T3 or stop backend polling." }
                                Repeater {
                                    model: root.providerGroups
                                    delegate: Rectangle {
                                        id: providerRow
                                        required property var modelData
                                        required property int index
                                        property var matches: root.allAccounts.filter(a => root.logo(a.provider) === modelData.id)
                                        property bool shown: !root.hiddenProviders.includes(modelData.id)
                                        property bool groupHeader: !!modelData.header
                                        Layout.fillWidth: true; implicitHeight: groupHeader ? groupLabel.implicitHeight+14 : providerContent.implicitHeight + 32; radius: 22; color: groupHeader ? "transparent" : root.cardColor
                                        opacity: root.pageStage(index+2)
                                        transform: Translate { x: -16*(1-providerRow.opacity); y: -4*(1-providerRow.opacity) }
                                        ColumnLayout {
                                            id: groupLabel; visible: providerRow.groupHeader; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; spacing: 4
                                            SectionTitle { text: providerRow.groupHeader ? providerRow.modelData.name : "" }
                                            Description { text: providerRow.groupHeader ? providerRow.modelData.note : ""; font.pixelSize: 11 }
                                        }
                                        ColumnLayout {
                                            id: providerContent; visible: !providerRow.groupHeader; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 16; spacing: 12
                                            RowLayout { Layout.fillWidth: true; spacing: 12
                                                ProviderIcon { Layout.preferredWidth: 38; Layout.preferredHeight: 38; name: providerRow.modelData.id; fallback: providerRow.modelData.name.slice(0,1) }
                                                ColumnLayout { Layout.fillWidth: true; spacing: 3
                                                    MText { text: providerRow.modelData.name; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                                    Description { text: providerRow.matches.length ? providerRow.matches.filter(a => !root.hiddenAccounts.includes(String(a.id))).length + " of " + providerRow.matches.length + " accounts selected" : providerRow.modelData.id === "codex" ? "No accounts discovered" : "Native quota adapter planned"; font.pixelSize: 11 }
                                                }
                                                MSwitch { checked: !root.hiddenProviders.includes(providerRow.modelData.id); onToggled: root.setHidden("hiddenProviders", providerRow.modelData.id, !checked) }
                                            }
                                            MText {
                                                visible: providerRow.matches.length > 0
                                                text: "LINKED ACCOUNTS"; color: root.muted
                                                font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.0
                                                Layout.topMargin: 4
                                            }
                                            Repeater {
                                                model: providerRow.matches
                                                delegate: Rectangle {
                                                    id: accountRow
                                                    required property var modelData
                                                    property bool shown: !root.hiddenAccounts.includes(String(modelData.id))
                                                    property real session: root.remaining(root.windowFor(modelData,300))
                                                    property real weekly: root.remaining(root.windowFor(modelData,10080))
                                                    Layout.fillWidth: true; implicitHeight: accountDetails.implicitHeight + 24
                                                    radius: 16; color: root.surface; border.width: 1; border.color: root.outline
                                                    opacity: providerRow.shown ? 1 : 0.55
                                                    ColumnLayout {
                                                        id: accountDetails
                                                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 12; spacing: 10
                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 10
                                                            Rectangle {
                                                                Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: 12; color: root.buttonColor
                                                                MText { anchors.centerIn: parent; text: String(accountRow.modelData.name || "Account").trim().slice(0,1).toUpperCase() || "A"; font.weight: Font.DemiBold; font.pixelSize: 16; color: root.onPrimaryContainer }
                                                            }
                                                            ColumnLayout {
                                                                Layout.fillWidth: true; spacing: 3
                                                                MText { text: accountRow.modelData.name || "Account"; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                                                RowLayout {
                                                                    spacing: 5
                                                                    Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: accountRow.modelData.status === "ok" ? root.primary : accountRow.modelData.status === "stale" ? root.weeklyColor : root.danger }
                                                                    MText { text: !accountRow.shown || !providerRow.shown ? "Hidden" : accountRow.modelData.status === "ok" ? "Available" : accountRow.modelData.status === "stale" ? "Stale cache" : "Unavailable"; font.pixelSize: 11; color: root.muted }
                                                                }
                                                            }
                                                            MSwitch { enabled: providerRow.shown; checked: accountRow.shown; onToggled: root.setHidden("hiddenAccounts", String(accountRow.modelData.id), !checked) }
                                                        }
                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 16
                                                            Repeater {
                                                                model: [{label:"Session",value:accountRow.session,tint:root.sessionColor},{label:"Weekly",value:accountRow.weekly,tint:root.weeklyColor}]
                                                                delegate: ColumnLayout {
                                                                    id: miniQuota
                                                                    required property var modelData
                                                                    Layout.fillWidth: true; spacing: 5
                                                                    RowLayout {
                                                                        Layout.fillWidth: true
                                                                        MText { text: miniQuota.modelData.label; font.pixelSize: 10; color: root.muted; Layout.fillWidth: true }
                                                                        MText { text: miniQuota.modelData.value < 0 ? "—" : Math.round(miniQuota.modelData.value) + "%"; font.family: root.monoFont; font.pixelSize: 11; color: miniQuota.modelData.tint }
                                                                    }
                                                                    Rectangle {
                                                                        Layout.fillWidth: true; implicitHeight: 4; radius: 2; color: root.track
                                                                        Rectangle { width: parent.width * Math.max(0,miniQuota.modelData.value) / 100 * root.pageStage(6); height: parent.height; radius: 2; color: miniQuota.modelData.tint }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Analytics"; Layout.fillWidth: true; spacing: 14
                                Description { opacity: root.pageStage(1); transform: Translate { x: -18*(1-root.pageStage(1)); y: -5*(1-root.pageStage(1)) }
                                    text: "Recorded subscription quota, not token consumption or actual billing. History starts after the new backend is installed." }
                                Flow { opacity: root.pageStage(2); transform: Translate { x: -18*(1-root.pageStage(2)); y: -5*(1-root.pageStage(2)) }
                                    Layout.fillWidth: true; spacing: 8
                                    Repeater { model: [{v:"1",n:"24h"},{v:"7",n:"7 days"},{v:"30",n:"30 days"},{v:"90",n:"90 days"}]
                                        delegate: Choice { required property var modelData; label: modelData.n; selected: root.analyticsPeriod === modelData.v; onChosen: root.analyticsPeriod = modelData.v }
                                    }
                                }
                                RowLayout { opacity: root.pageStage(3); transform: Translate { x: -18*(1-root.pageStage(3)); y: -5*(1-root.pageStage(3)) }
                                    Layout.fillWidth: true
                                    Choice { label: "Session"; selected: root.analyticsMetric === "session"; onChosen: root.analyticsMetric = "session" }
                                    Choice { label: "Weekly"; selected: root.analyticsMetric === "weekly"; onChosen: root.analyticsMetric = "weekly" }
                                    Item { Layout.fillWidth: true }
                                    Choice { label: "Line"; selected: prefs.chartMode === "line"; onChosen: prefs.chartMode = "line" }
                                    Choice { label: "Bars"; selected: prefs.chartMode === "bars"; onChosen: prefs.chartMode = "bars" }
                                }
                                Rectangle { opacity: root.pageStage(4); transform: Translate { x: -18*(1-root.pageStage(4)); y: -5*(1-root.pageStage(4)) }
                                    
                                    id: analyticsGraph
                                    Layout.fillWidth: true; implicitHeight: 280; radius: 22; color: root.materialCard
                                    Item {
                                        x: 18; y: 18; width: Math.max(0,analyticsGraph.width-36)*root.pageStage(6); height: Math.max(1,analyticsGraph.height-36); clip: true
                                    Canvas {
                                        id: plot; width: Math.max(1,analyticsGraph.width-36); height: Math.max(1,analyticsGraph.height-36)
                                        property var samples: root.series()
                                        property string mode: prefs.chartMode
                                        property string period: root.analyticsPeriod
                                        property color fg: root.primary
                                        property color secondary: root.weeklyColor
                                        property color gridColor: root.track
                                        property color labelColor: root.muted
                                        onSamplesChanged: requestPaint()
                                        onModeChanged: requestPaint()
                                        onPeriodChanged: requestPaint()
                                        onFgChanged: requestPaint()
                                        onSecondaryChanged: requestPaint()
                                        onGridColorChanged: requestPaint()
                                        onLabelColorChanged: requestPaint()
                                        onWidthChanged: requestPaint()
                                        onHeightChanged: requestPaint()
                                        onPaint: {
                                            let c = getContext("2d"); c.reset()
                                            let left=38, top=12, w=Math.max(1,width-left-8), h=Math.max(1,height-top-30)
                                            c.font="11px sans-serif"; c.fillStyle=labelColor
                                            for(let v=0;v<=100;v+=25) { let y=top+h*(1-v/100); c.strokeStyle=gridColor; c.beginPath(); c.moveTo(left,y); c.lineTo(left+w,y); c.stroke(); c.fillText(v+"%",0,y+4) }
                                            let end=Date.now()/1000, start=end-Number(period)*86400
                                            let groups={}
                                            for(let p of samples) { if(p.time<start || p.time>end) continue; let key=String(p.id); if(!groups[key]) groups[key]=[]; groups[key].push(p) }
                                            let keys=Object.keys(groups).sort()
                                            keys.forEach((key,i)=>{
                                                let pts=groups[key].sort((a,b)=>a.time-b.time); let colour=i%2===0?fg:secondary
                                                c.strokeStyle=colour; c.fillStyle=colour; c.lineWidth=2
                                                if(mode==="line") {
                                                    c.beginPath()
                                                    pts.forEach((p,j)=>{let x=left+w*(p.time-start)/(end-start), y=top+h*(1-p.remaining/100); if(j===0)c.moveTo(x,y);else c.lineTo(x,y)})
                                                    c.stroke()
                                                    if(pts.length===1){let p=pts[0];c.beginPath();c.arc(left+w*(p.time-start)/(end-start),top+h*(1-p.remaining/100),3,0,Math.PI*2);c.fill()}
                                                } else {
                                                    let buckets=Number(period)===1?24:Math.min(90,Number(period))
                                                    let last={}
                                                    pts.forEach(p=>{let b=Math.max(0,Math.min(buckets-1,Math.floor((p.time-start)/(end-start)*buckets)));last[b]=p})
                                                    let bw=w/buckets
                                                    Object.keys(last).forEach(b=>{let p=last[b], bh=h*p.remaining/100;let sw=Math.max(1,(bw-2)/keys.length);c.fillRect(left+Number(b)*bw+i*sw,top+h-bh,sw,bh)})
                                                }
                                            })
                                            c.fillStyle=labelColor; c.fillText(period==="1"?"24h ago":period+"d ago",left,height-3); c.fillText("Now",Math.max(left,width-30),height-3)
                                            if(!keys.length) { c.fillText("No samples for this window yet",left+8,top+h/2) }
                                        }
                                    }
                                    }
                                }
                                Description { opacity: root.pageStage(5); transform: Translate { x: -18*(1-root.pageStage(5)); y: -5*(1-root.pageStage(5)) }
                                    text: root.analyticsStatus + " · Remaining quota (%) · Bars show the last observation in each time bucket." }
                                SectionTitle { opacity: root.pageStage(6); transform: Translate { x: -18*(1-root.pageStage(6)); y: -5*(1-root.pageStage(6)) }
                                    text: "Account legend" }
                                Repeater {
                                    model: Array.from(new Set(root.series().map(p => String(p.id)))).sort()
                                    delegate: RowLayout {
                                        required property string modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        Rectangle { Layout.preferredWidth: 12; Layout.preferredHeight: 12; radius: 6; color: index % 2 === 0 ? root.primary : root.weeklyColor }
                                        MText { Layout.fillWidth: true; elide: Text.ElideRight; text: (root.series().find(p => String(p.id) === modelData) || {}).name || modelData }
                                    }
                                }
                                SectionTitle { opacity: root.pageStage(7); transform: Translate { x: -18*(1-root.pageStage(7)); y: -5*(1-root.pageStage(7)) }
                                    text: "Token and cost analytics" }
                                Description { opacity: root.pageStage(8); transform: Translate { x: -18*(1-root.pageStage(8)); y: -5*(1-root.pageStage(8)) }
                                    text: "T3 historical token usage and API-equivalent costs are not connected yet. No fabricated estimates are shown." }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Behaviour"; Layout.fillWidth: true; spacing: 14
                                RowLayout { opacity: root.pageStage(1); transform: Translate { x: -18*(1-root.pageStage(1)); y: -5*(1-root.pageStage(1)) }
                                    MText { text: "Hover activation"; Layout.fillWidth: true } MSwitch { checked: prefs.hoverEnabled; onToggled: prefs.hoverEnabled = checked } }
                                SectionTitle { opacity: root.pageStage(2); transform: Translate { x: -18*(1-root.pageStage(2)); y: -5*(1-root.pageStage(2)) }
                                    text: "Activation position" }
                                Rectangle { opacity: root.pageStage(3); transform: Translate { x: -18*(1-root.pageStage(3)); y: -5*(1-root.pageStage(3)) }
                                    
                                    Layout.fillWidth: true; implicitHeight: 144; radius: 20; color: root.materialCard
                                    GridLayout { anchors.fill: parent; anchors.margins: 12; columns: 3; rowSpacing: 6; columnSpacing: 6
                                        Repeater {
                                            model: ["top-left","top-center","top-right","left-center","","right-center","bottom-left","bottom-center","bottom-right"]
                                            delegate: Choice { required property string modelData; required property int index; Layout.fillWidth: true; Layout.fillHeight: true; label: ["↖","↑","↗","←","SCREEN","→","↙","↓","↘"][index]; selected: prefs.hotspot === modelData; enabled: modelData !== ""; onChosen: if(modelData) prefs.hotspot = modelData }
                                        }
                                    }
                                }
                                Description { opacity: root.pageStage(4); transform: Translate { x: -18*(1-root.pageStage(4)); y: -5*(1-root.pageStage(4)) }
                                    text: prefs.hotspot.replace("-", " ") }
                                RowLayout { opacity: root.pageStage(5); transform: Translate { x: -18*(1-root.pageStage(5)); y: -5*(1-root.pageStage(5)) }
                                    MText { text: "Hotspot size · " + prefs.hotspotSize + " px"; Layout.fillWidth: true } MSlider { from: 8; to: 48; stepSize: 2; value: prefs.hotspotSize; onMoved: prefs.hotspotSize = Math.round(value) } }
                                RowLayout { opacity: root.pageStage(6); transform: Translate { x: -18*(1-root.pageStage(6)); y: -5*(1-root.pageStage(6)) }
                                    MText { text: "Dismiss delay · " + prefs.dismissDelay + " ms"; Layout.fillWidth: true } MSlider { from: 100; to: 1000; stepSize: 50; value: prefs.dismissDelay; onMoved: prefs.dismissDelay = Math.round(value) } }
                                RowLayout { opacity: root.pageStage(7); transform: Translate { x: -18*(1-root.pageStage(7)); y: -5*(1-root.pageStage(7)) }
                                    MText { text: "Cache refresh · " + prefs.cacheSeconds + " s"; Layout.fillWidth: true } MSlider { from: 2; to: 30; stepSize: 1; value: prefs.cacheSeconds; onMoved: prefs.cacheSeconds = Math.round(value) } }
                                Description { opacity: root.pageStage(8); transform: Translate { x: -18*(1-root.pageStage(8)); y: -5*(1-root.pageStage(8)) }
                                    text: "The daemon collects quotas every three minutes. This setting only changes how often the drawer reads its cache." }
                                Choice { opacity: root.pageStage(9); transform: Translate { x: -18*(1-root.pageStage(9)); y: -5*(1-root.pageStage(9)) }
                                    label: "Restore defaults"; onChosen: { prefs.followTheme=true; prefs.colorScheme="mono"; prefs.hoverEnabled=true; prefs.motionMs=1100; prefs.dismissDelay=350; prefs.layoutWidth=440; prefs.cacheSeconds=5; prefs.viewMode="grid"; prefs.hotspot="top-right"; prefs.staggerEnabled=true; prefs.hiddenProviders="[]"; prefs.hiddenAccounts="[]"; prefs.chartMode="line"; prefs.hotspotSize=18; prefs.fontChoice="auto"; prefs.cardRadius=24; prefs.edgeFades=true; prefs.fadeDepth=28; prefs.localShortcutsEnabled=true; prefs.globalShortcutsEnabled=true; prefs.shortcutBindings="{}"; prefs.bindSyntax="conf"; prefs.motionStyle="liquid"; prefs.glassEnabled=false; prefs.glassOpacity=88; prefs.materialMode="solid"; prefs.liquidTint=38; prefs.refractionStrength=0.8; prefs.glassDispersion=0.35; prefs.glassEdgeHeight=28 } }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Shortcuts"; Layout.fillWidth: true; spacing: 14
                                SectionTitle { opacity: root.pageStage(1); transform: Translate { x: -18*(1-root.pageStage(1)); y: -5*(1-root.pageStage(1)) }
                                    text: "Desktop shortcuts" }
                                Description { opacity: root.pageStage(2); transform: Translate { x: -18*(1-root.pageStage(2)); y: -5*(1-root.pageStage(2)) }
                                    text: "Open aether from anywhere in Hyprland. Choose a modifier and key, then copy the generated configuration into your own keybind file. Existing desktop bindings are never changed automatically." }
                                RowLayout { opacity: root.pageStage(3); transform: Translate { x: -18*(1-root.pageStage(3)); y: -5*(1-root.pageStage(3)) }
                                    
                                    Layout.fillWidth: true
                                    MText { text: "Generate desktop bindings"; Layout.fillWidth: true }
                                    MSwitch { checked: prefs.globalShortcutsEnabled; onToggled: prefs.globalShortcutsEnabled = checked }
                                }
                                Repeater {
                                    model: root.shortcutActions
                                    delegate: Rectangle {
                                        id: actionCard
                                        required property var modelData
                                        property var binding: root.bindingFor(modelData)
                                        Layout.fillWidth: true; implicitHeight: bindingContent.implicitHeight + 24
                                        radius: 18; color: root.materialCard
                                        border.width: 1; border.color: root.outline
                                        opacity: prefs.globalShortcutsEnabled ? 1 : 0.55
                                        ColumnLayout {
                                            id: bindingContent
                                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 12
                                            spacing: 8
                                            MText { text: actionCard.modelData.label; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                            Description { text: actionCard.modelData.note; font.pixelSize: 11 }
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 8
                                                LiquidSelect {
                                                    id: modifierCombo
                                                    prominent: true
                                                    Layout.fillWidth: true
                                                    model: root.shortcutModifiers
                                                    currentIndex: root.shortcutModifiers.indexOf(actionCard.binding.mods)
                                                    enabled: prefs.globalShortcutsEnabled
                                                    font.family: root.sans
                                                    palette.button: root.track; palette.buttonText: root.foreground
                                                    palette.window: root.cardColor; palette.windowText: root.foreground; palette.text: root.foreground; palette.base: root.cardColor
                                                    palette.highlight: root.primary; palette.highlightedText: root.onAccent
                                                    onActivated: root.setBinding(actionCard.modelData, "mods", model[index])
                                                }
                                                LiquidSelect {
                                                    id: keyCombo
                                                    prominent: true
                                                    Layout.preferredWidth: 104
                                                    model: root.shortcutKeys
                                                    currentIndex: root.shortcutKeys.indexOf(actionCard.binding.key)
                                                    enabled: prefs.globalShortcutsEnabled && actionCard.binding.mods !== "Disabled"
                                                    font.family: root.monoFont
                                                    palette.button: root.track; palette.buttonText: root.foreground
                                                    palette.window: root.cardColor; palette.windowText: root.foreground; palette.text: root.foreground; palette.base: root.cardColor
                                                    palette.highlight: root.primary; palette.highlightedText: root.onAccent
                                                    onActivated: root.setBinding(actionCard.modelData, "key", model[index])
                                                }
                                            }
                                        }
                                    }
                                }
                                Description { opacity: root.pageStage(4); transform: Translate { x: -18*(1-root.pageStage(4)); y: -5*(1-root.pageStage(4)) }
                                    visible: prefs.globalShortcutsEnabled && root.duplicateBindings; color: root.danger; text: "Two aether actions use the same shortcut. Choose different combinations before copying." }
                                RowLayout { opacity: root.pageStage(5); transform: Translate { x: -18*(1-root.pageStage(5)); y: -5*(1-root.pageStage(5)) }
                                    
                                    Layout.fillWidth: true
                                    MText { text: "Hyprland configuration"; Layout.fillWidth: true; font.weight: Font.Medium }
                                    LiquidSelect { Layout.preferredWidth: 160; model: ["Legacy .conf","Lua"]; currentIndex: prefs.bindSyntax === "lua" ? 1 : 0; onActivated: prefs.bindSyntax = index === 1 ? "lua" : "conf" }
                                }
                                TextArea { opacity: root.pageStage(6); transform: Translate { x: -18*(1-root.pageStage(6)); y: -5*(1-root.pageStage(6)) }
                                    
                                    id: bindingText
                                    Layout.fillWidth: true; Layout.preferredHeight: Math.max(120, Math.min(240, contentHeight + 24))
                                    readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere
                                    focusPolicy: Qt.NoFocus; activeFocusOnPress: false
                                    text: root.hyprlandBindings
                                    color: root.foreground; selectionColor: root.primary; selectedTextColor: root.onAccent
                                    font.family: root.monoFont; font.pixelSize: 11; padding: 12
                                    background: Rectangle { radius: 16; color: root.cardColor; border.width: 1; border.color: root.outline }
                                }
                                RowLayout { opacity: root.pageStage(7); transform: Translate { x: -18*(1-root.pageStage(7)); y: -5*(1-root.pageStage(7)) }
                                    
                                    Layout.fillWidth: true
                                    Choice { label: "Reset bindings"; onChosen: prefs.shortcutBindings = "{}" }
                                    Item { Layout.fillWidth: true }
                                    Choice {
                                        label: "Copy configuration"
                                        enabled: prefs.globalShortcutsEnabled && !root.duplicateBindings && root.hyprlandBindings.length > 0
                                        opacity: enabled ? 1 : 0.45
                                        onChosen: { bindingText.selectAll(); bindingText.copy() }
                                    }
                                }
                                Description { opacity: root.pageStage(8); transform: Translate { x: -18*(1-root.pageStage(8)); y: -5*(1-root.pageStage(8)) }
                                    text: "Replace any previously installed aether binds in your Hyprland configuration, check for conflicts with existing desktop shortcuts, then reload Hyprland. Changing or disabling a binding here only updates the generated text; remove the previous compositor binding yourself." }
                                SectionTitle { opacity: root.pageStage(9); transform: Translate { x: -18*(1-root.pageStage(9)); y: -5*(1-root.pageStage(9)) }
                                    text: "Inside the control centre" }
                                RowLayout { opacity: root.pageStage(10); transform: Translate { x: -18*(1-root.pageStage(10)); y: -5*(1-root.pageStage(10)) }
                                    
                                    Layout.fillWidth: true
                                    MText { text: "Enable in-app shortcuts"; Layout.fillWidth: true }
                                    MSwitch { checked: prefs.localShortcutsEnabled; onToggled: prefs.localShortcutsEnabled = checked }
                                }
                                Repeater {
                                    model: root.settingsPages.concat(["Refresh local view","Close control centre"])
                                    delegate: Rectangle {
                                        id: localRow
                                        required property string modelData
                                        required property int index
                                        Layout.fillWidth: true; implicitHeight: 42; radius: 12; color: root.cardColor
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                            MText { text: localRow.modelData; Layout.fillWidth: true }
                                            Rectangle {
                                                implicitWidth: keyLabel.implicitWidth + 16; implicitHeight: 26; radius: 7; color: root.track
                                                MText { id: keyLabel; anchors.centerIn: parent; text: localRow.index < root.settingsPages.length ? "Ctrl+" + (localRow.index + 1) : localRow.index === root.settingsPages.length ? "Ctrl+R" : "Esc"; font.family: root.monoFont; font.pixelSize: 11 }
                                            }
                                        }
                                    }
                                }
                                Description { opacity: root.pageStage(11); transform: Translate { x: -18*(1-root.pageStage(11)); y: -5*(1-root.pageStage(11)) }
                                    text: "In-app shortcuts work when the control centre has keyboard focus. The hover drawer deliberately does not steal focus." }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Updates"; Layout.fillWidth: true; spacing: 16
                                Description { opacity: root.pageStage(1); transform: Translate { x: -18*(1-root.pageStage(1)); y: -5*(1-root.pageStage(1)) }
                                    text: "Keep aether up to date from its official GitHub repository. Automatic installation is opt-in. Updates do not modify your project checkout, credentials or preferences." }
                                Rectangle { opacity: root.pageStage(2); transform: Translate { x: -18*(1-root.pageStage(2)); y: -5*(1-root.pageStage(2)) }
                                    
                                    Layout.fillWidth: true; implicitHeight: updateCard.implicitHeight + 32; radius: 24; color: root.cardColor
                                    ColumnLayout {
                                        id: updateCard; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 16; spacing: 10
                                        SectionTitle { text: "Installed build" }
                                        MText { text: "v" + root.version; font.pixelSize: 34; font.weight: Font.DemiBold }
                                        Description { text: root.updateInfo.installed ? "Commit " + root.updateInfo.installed.slice(0,12) : "Commit receipt unavailable · run full installer" }
                                        Description { text: updateReader.running && root.updateAction !== "status" ? "Checking for updates…" : root.updateInfo.message || "No update check yet" }
                                        Description { visible: !!root.updateInfo.candidate; text: "Candidate " + String(root.updateInfo.candidate || "").slice(0,12) }
                                        Description { visible: !!root.updateInfo.checked; text: "Last checked " + (root.updateInfo.checked || "") }
                                    }
                                }
                                RowLayout { opacity: root.pageStage(3); transform: Translate { x: -18*(1-root.pageStage(3)); y: -5*(1-root.pageStage(3)) }
                                    
                                    Layout.fillWidth: true
                                    MText { text: "Automatically install updates"; Layout.fillWidth: true }
                                    MSwitch { checked: prefs.autoUpdate; onToggled: { prefs.autoUpdate = checked; prefs.sync() } }
                                }
                                SectionTitle { opacity: root.pageStage(4); transform: Translate { x: -18*(1-root.pageStage(4)); y: -5*(1-root.pageStage(4)) }
                                    text: "Update channel" }
                                RowLayout { opacity: root.pageStage(5); transform: Translate { x: -18*(1-root.pageStage(5)); y: -5*(1-root.pageStage(5)) }
                                    
                                    Layout.fillWidth: true
                                    LiquidSelect { Layout.fillWidth: true; model: ["Stable releases","Development"]; currentIndex: prefs.updateChannel === "development" ? 1 : 0; onActivated: { prefs.updateChannel = index === 1 ? "development" : "stable"; prefs.sync(); root.runUpdater("status") } }
                                }
                                Description { opacity: root.pageStage(6); transform: Translate { x: -18*(1-root.pageStage(6)); y: -5*(1-root.pageStage(6)) }
                                    text: prefs.updateChannel === "stable" ? "Only published, non-prerelease GitHub releases. Until a release is published, there is no stable update." : "Tracks main commits. Development builds may introduce regressions; choose Stable if you prefer fewer changes." }
                                RowLayout { opacity: root.pageStage(7); transform: Translate { x: -18*(1-root.pageStage(7)); y: -5*(1-root.pageStage(7)) }
                                    
                                    Layout.fillWidth: true
                                    Choice { label: "Check for updates"; enabled: !updateReader.running && !root.updateInfo.busy; onChosen: root.runUpdater("check") }
                                    Choice { label: "Install update"; enabled: !updateReader.running && !root.updateInfo.busy; onChosen: root.runUpdater("apply") }
                                    Choice { label: "Roll back"; enabled: !updateReader.running && !root.updateInfo.busy && !!root.updateInfo.rollbackAvailable; onChosen: root.runUpdater("rollback") }
                                }
                                Description { opacity: root.pageStage(8); transform: Translate { x: -18*(1-root.pageStage(8)); y: -5*(1-root.pageStage(8)) }
                                    text: "The systemd user timer checks every six hours when automatic installation is enabled. The updater builds before replacing files, refuses downgrades or divergent commits, and restores previous files on installation errors. A previous build is retained for manual rollback. No sudo. If Quickshell does not reload automatically, restart only aether." }
                                LinkRow { opacity: root.pageStage(9); transform: Translate { x: -18*(1-root.pageStage(9)); y: -5*(1-root.pageStage(9)) }
                                    label: "Release history ↗"; url: "https://github.com/maynkudu/aether-ai/releases" }
                                LinkRow { opacity: root.pageStage(10); transform: Translate { x: -18*(1-root.pageStage(10)); y: -5*(1-root.pageStage(10)) }
                                    label: "Development commits ↗"; url: "https://github.com/maynkudu/aether-ai/commits/main" }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "About"; Layout.fillWidth: true; spacing: 16
                                Rectangle { opacity: root.pageStage(1); transform: Translate { x: -18*(1-root.pageStage(1)); y: -5*(1-root.pageStage(1)) }
                                    
                                    Layout.fillWidth: true; implicitHeight: 196; radius: 26; color: root.materialCard
                                    ColumnLayout { anchors.fill: parent; anchors.margins: 24; spacing: 8
                                        RowLayout { Layout.fillWidth: true
                                            Description { text: "INDEPENDENT SOFTWARE"; font.pixelSize: 11; font.letterSpacing: 1.3 }
                                            Choice { label: "MIT"; onChosen: Qt.openUrlExternally("https://github.com/maynkudu/aether-ai/blob/main/LICENSE") }
                                        }
                                        MText { text: "aether.ai"; font.pixelSize: 48; font.weight: Font.DemiBold; font.letterSpacing: -2.2; Layout.fillWidth: true; elide: Text.ElideRight }
                                        Description { text: "Intelligence, within limits." }
                                        Item { Layout.fillHeight: true }
                                        RowLayout { Layout.fillWidth: true
                                            MText { text: "v" + root.version; font.family: root.monoFont; color: root.primary }
                                            Item { Layout.fillWidth: true }
                                            Description { text: "Rust × Quickshell"; Layout.fillWidth: false }
                                        }
                                    }
                                }
                                SectionTitle { opacity: root.pageStage(2); transform: Translate { x: -18*(1-root.pageStage(2)); y: -5*(1-root.pageStage(2)) }
                                    text: "Made by" }
                                LinkRow { opacity: root.pageStage(3); transform: Translate { x: -18*(1-root.pageStage(3)); y: -5*(1-root.pageStage(3)) }
                                    label: "maynkudu · Creator"; url: "https://github.com/maynkudu" }
                                LinkRow { opacity: root.pageStage(4); transform: Translate { x: -18*(1-root.pageStage(4)); y: -5*(1-root.pageStage(4)) }
                                    label: "Project contributors"; url: "https://github.com/maynkudu/aether-ai/graphs/contributors" }
                                SectionTitle { opacity: root.pageStage(5); transform: Translate { x: -18*(1-root.pageStage(5)); y: -5*(1-root.pageStage(5)) }
                                    text: "Open-source community" }
                                LinkRow { opacity: root.pageStage(6); transform: Translate { x: -18*(1-root.pageStage(6)); y: -5*(1-root.pageStage(6)) }
                                    label: "GitHub repository"; githubIcon: true; url: "https://github.com/maynkudu/aether-ai" }
                                LinkRow { opacity: root.pageStage(7); transform: Translate { x: -18*(1-root.pageStage(7)); y: -5*(1-root.pageStage(7)) }
                                    label: "Issues & feature requests"; url: "https://github.com/maynkudu/aether-ai/issues" }
                                LinkRow { opacity: root.pageStage(8); transform: Translate { x: -18*(1-root.pageStage(8)); y: -5*(1-root.pageStage(8)) }
                                    label: "Changelog"; url: "https://github.com/maynkudu/aether-ai/blob/main/CHANGELOG.md" }
                                LinkRow { opacity: root.pageStage(9); transform: Translate { x: -18*(1-root.pageStage(9)); y: -5*(1-root.pageStage(9)) }
                                    label: "MIT license"; url: "https://github.com/maynkudu/aether-ai/blob/main/LICENSE" }
                                LinkRow { opacity: root.pageStage(10); transform: Translate { x: -18*(1-root.pageStage(10)); y: -5*(1-root.pageStage(10)) }
                                    label: "Brand artwork sources"; url: "https://github.com/maynkudu/aether-ai/blob/main/shell/BRAND-ASSETS.md" }
                                Description { opacity: root.pageStage(11); transform: Translate { x: -18*(1-root.pageStage(11)); y: -5*(1-root.pageStage(11)) }
                                    text: "Local-first. No telemetry. No inference proxy. No changes to T3 Code or Caelestia." }
                            }
                        }
                        }
                        ScrollFade { anchors.fill: pageScroll; viewport: pageScroll }
                        }
                    }
                }
            }
        }
    }
}
