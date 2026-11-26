import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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
    // Keep existing gauge delegates alive across cache refreshes.
    property var ringAccountIds: []
    function syncRingAccounts() {
        let ids = accounts.map(a => String(a.id))
        if (JSON.stringify(ids) !== JSON.stringify(ringAccountIds)) ringAccountIds = ids
    }
    onAccountsChanged: syncRingAccounts()
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
        {id:"analytics",label:"Open analytics",note:"Jump directly to token usage",mods:"SUPER ALT",key:"U"},
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
        if (settingsTab !== name) { pageSpring.jump(0); pageDataClock.jump(0) }
        settingsTab = name
        if (name === "Updates") runUpdater("status")
        pageScroll.cancelFlick()
        pageScroll.contentY = pageScroll.originY
        // Reset again after the new page layout has had a chance to settle.
        Qt.callLater(function() { if (root.settingsTab === name) pageScroll.contentY = pageScroll.originY })
        if (name === "Analytics") refreshAnalytics()
    }
    function openSettings(name) {
        hide()
        settingsOpen = true
        if (name) selectPage(name)
    }
    function refreshView() {
        if (!reader.running) reader.running = true
        if (settingsOpen) refreshAnalytics()
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
    property string analyticsMetric: "tokens"
    property var analyticsSamples: []
    property string analyticsStatus: "No local token usage found"
    Process {
        id: analyticsReader
        command: [Quickshell.env("HOME") + "/.local/bin/aether", "analytics", root.analyticsPeriod]
        stdout: StdioCollector { onStreamFinished: {
            try {
                let data = JSON.parse(text)
                root.analyticsSamples = data.samples || []
                root.analyticsStatus = root.analyticsSamples.length ? "Local Codex session logs" : "No local token usage found for this period"
            } catch(e) { root.analyticsSamples = []; root.analyticsStatus = "Token usage unavailable; install the updated backend" }
        } }
    }
    function refreshAnalytics() { if (!analyticsReader.running) analyticsReader.running = true }
    property var analyticsRows: {
        return analyticsSamples.filter(a => !hiddenProviders.includes(logo(a.provider)) && !hiddenAccounts.includes(String(a.id)))
    }
    property var analyticsTotals: {
        let result = {input:0,cached:0,output:0,reasoning:0,total:0,requests:0,cost:0,costComplete:true}
        for (let sample of analyticsRows) {
            result.input += Number(sample.inputTokens || 0)
            result.cached += Number(sample.cachedInputTokens || 0)
            result.output += Number(sample.outputTokens || 0)
            result.reasoning += Number(sample.reasoningTokens || 0)
            result.total += Number(sample.totalTokens || 0)
            result.requests += Number(sample.requestCount || 0)
            if (typeof sample.estimatedCostUsd === "number") result.cost += sample.estimatedCostUsd
            else result.costComplete = false
        }
        return result
    }
    property var analyticsAccounts: {
        let grouped = {}
        for (let sample of analyticsRows) {
            let id = String(sample.id)
            if (!grouped[id]) grouped[id] = {id:id,name:sample.name,authKind:sample.authKind,input:0,output:0,requests:0}
            grouped[id].input += Number(sample.inputTokens || 0)
            grouped[id].output += Number(sample.outputTokens || 0)
            grouped[id].requests += Number(sample.requestCount || 0)
        }
        return Object.values(grouped).sort((a,b) => b.input + b.output - a.input - a.output)
    }
    property var analyticsProviders: Array.from(new Set(analyticsRows.map(sample => String(sample.provider || "Other")))).sort()
    function providerColor(provider) {
        switch (logo(provider)) {
        case "codex": return primary
        case "claude": return "#ef9664"
        case "opencode": return "#70b4d8"
        case "grok": return "#9b91e5"
        case "pi": return "#57b896"
        case "openrouter": return "#b68bdd"
        case "deepseek": return "#4c9bd1"
        case "agentrouter": return "#e6bb65"
        case "freegg": return "#8fb879"
        default: return weeklyColor
        }
    }
    property var analyticsPlot: {
        if (analyticsMetric === "cost" && !analyticsTotals.costComplete) return []
        let interval = analyticsPeriod === "1" ? 3600 : 86400
        let now = Math.floor(Date.now()/1000)
        let start = Math.floor((now-Number(analyticsPeriod)*86400)/interval)*interval
        let end = Math.floor(now/interval)*interval
        return analyticsProviders.map(provider => {
            let values = ({})
            for (let sample of analyticsRows) {
                if (String(sample.provider || "Other") !== provider) continue
                let time = Math.floor(Number(sample.time)/interval)*interval
                let value = analyticsMetric === "cost" ? sample.estimatedCostUsd : sample.totalTokens
                if (analyticsMetric === "cost" && typeof value !== "number") continue
                values[time] = (values[time] || 0) + Number(value || 0)
            }
            let points = []
            for (let time=start;time<=end;time+=interval) points.push({time:time,value:values[time] || 0})
            return {provider:provider,points:points}
        })
    }
    function countText(value) {
        value = Number(value || 0)
        if (value >= 1000000000) return (value/1000000000).toFixed(1) + "B"
        if (value >= 1000000) return (value/1000000).toFixed(1) + "M"
        if (value >= 10000) return (value/1000).toFixed(1) + "K"
        return value.toLocaleString()
    }
    function costText(value) {
        if (value === null || value === undefined || !isFinite(Number(value))) return "—"
        if (Number(value) < 0.01) return "<$0.01"
        return "$" + Number(value).toFixed(2)
    }
    onAnalyticsPeriodChanged: { refreshAnalytics(); if (settingsOpen && settingsTab === "Analytics") pageDataClock.jump(0) }
    onAnalyticsMetricChanged: if (settingsOpen && settingsTab === "Analytics") pageDataClock.jump(0)
    onSettingsOpenChanged: if (settingsOpen) { pageSpring.jump(0); pageDataClock.jump(0); if (!reader.running) reader.running = true; refreshAnalytics(); if (settingsTab === "Updates") runUpdater("status") } else if (activeDropdown) activeDropdown.close()
    Timer { interval: 30000; repeat: true; running: root.settingsOpen; onTriggered: { root.now = Date.now(); root.refreshAnalytics() } }
    property string accountSnapshot: ""
    property var brandIndex: ({})
    property string brandDirectory: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/aether/brand-icons"
    Component.onCompleted: {
        if (prefs.motionRevision < 5) {
            // Revision 3 stored data timing in the interface preference.
            if (prefs.motionRevision === 3) {
                prefs.dataMotionMs = Math.max(1200,Math.min(2800,prefs.motionMs))
                prefs.motionMs = 240
            }
            if (prefs.motionMs === 820) prefs.motionMs = 240
            if (prefs.dataMotionMs === 1800) prefs.dataMotionMs = 450
            prefs.motionRevision = 5
        }
        if (prefs.hotspotRevision < 1) {
            if (prefs.hotspotSize < 32) prefs.hotspotSize = 40
            prefs.hotspotRevision = 1
        }
        syncRingAccounts()
        scheduleFullscreenRefresh()
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
    Behavior on animatedHeight { NumberAnimation { duration: root.motionDuration(0.55); easing.type: Easing.InOutSine } }
    // Independent interface and data clocks, advanced by Qt's animation driver.
    function motionDuration(factor) {
        if (prefs.motionStyle === "reduced") return 0
        return Math.round(Math.max(120, prefs.motionMs) * factor * (prefs.motionStyle === "smooth" ? 1.12 : 1))
    }
    function controlDuration() { return prefs.motionStyle === "reduced" ? 0 : Math.max(80,Math.min(140,root.motionDuration(0.4))) }
    function dataDuration(factor) {
        return prefs.motionStyle === "reduced" ? 0 : Math.round(Math.max(200,prefs.dataMotionMs)*factor)
    }
    component MotionValue: Item {
        id: motion
        visible: false; width: 0; height: 0
        property real targetValue: 0
        property real value: 0
        property real factor: 1
        property bool dataMotion: false
        property bool proportional: false
        property int curve: Easing.OutCubic
        property bool instant: prefs.motionStyle === "reduced"
        property bool ready: false
        function retarget() {
            if (!ready) return
            tween.stop()
            if (instant || Math.abs(targetValue-value) < 0.00001) {
                value = targetValue
                return
            }
            // Reverse from the current position, rather than resetting it.
            tween.from = value
            tween.to = targetValue
            tween.duration = Math.max(1, Math.round((dataMotion ? root.dataDuration(factor) : root.motionDuration(factor)) * (proportional ? Math.min(1, Math.abs(targetValue-value)) : 1)))
            tween.start()
        }
        function jump(next) {
            tween.stop()
            value = instant ? targetValue : next
            retarget()
        }
        onTargetValueChanged: retarget()
        onInstantChanged: retarget()
        Component.onCompleted: {
            value = targetValue
            ready = true
        }
        NumberAnimation {
            id: tween
            target: motion; property: "value"
            easing.type: motion.curve
        }
    }
    function unit(v) { return Math.max(0, Math.min(1, v)) }
    function smooth(t) { t = unit(t); return t*t*(3-2*t) }
    function quintic(t) { t = unit(t); return t*t*t*(t*(t*6-15)+10) }
    MotionValue { id: drawerSpring; targetValue: root.opened ? 1 : 0; proportional: true; factor: root.opened ? 1 : 2/3; curve: root.opened ? Easing.OutCubic : Easing.InCubic }
    property real reveal: unit(drawerSpring.value)
    MotionValue { id: drawerContentSpring; targetValue: root.opened ? 1 : 0; factor: root.opened ? 1.20 : 2/3; proportional: true; curve: Easing.Linear }
    MotionValue { id: settingsSpring; targetValue: root.settingsOpen ? 1 : 0; proportional: true; factor: root.settingsOpen ? 1 : 2/3 }
    property real settingsReveal: unit(settingsSpring.value)
    MotionValue { id: settingsContentSpring; targetValue: root.settingsOpen ? 1 : 0; factor: 1.05; proportional: true; curve: Easing.Linear }
    MotionValue { id: pageSpring; targetValue: root.settingsOpen ? 1 : 0; factor: 1.05; proportional: true; curve: Easing.Linear }
    MotionValue { id: pageDataClock; targetValue: root.settingsOpen ? 1 : 0; factor: 1.40; dataMotion: true; proportional: true; curve: Easing.Linear }
    // Ring fill has its own constant-rate clock, independent of the panel
    // reveal and opacity. Both arcs start together and settle at their data.
    MotionValue { id: ringClock; targetValue: root.opened ? 1 : 0; factor: 1.40; dataMotion: true; proportional: true; curve: Easing.Linear }
    function ringProgress(i) {
        if (prefs.motionStyle === "reduced") return 1
        let delay = 0.20 + (prefs.staggerEnabled ? Math.min(i,8)*0.015 : 0)
        return unit((ringClock.value-delay)/0.68)
    }
    function heightProgress(p) { return p }
    function pageStage(i) {
        if (prefs.motionStyle === "reduced") return 1
        let delay = prefs.staggerEnabled ? Math.min(0.5,Math.min(120,Math.max(0,i)*12)/Math.max(1,root.motionDuration(1.05))) : 0
        return smooth((unit(pageSpring.value)-delay)/(1-delay))
    }
    function pageDataProgress(i) {
        if (prefs.motionStyle === "reduced") return 1
        let delay = 0.20 + (prefs.staggerEnabled ? Math.min(i,8)*0.015 : 0)
        return unit((pageDataClock.value-delay)/0.68)
    }
    component ItemGrowth: Scale {
        property real stage: 1
        origin.x: 0; origin.y: 0
        xScale: 0.985 + 0.015*stage
        yScale: 0.985 + 0.015*stage
    }
    property real finalPanelX: 6 + (drawer.width-12-panelWidth)*ax
    property real finalPanelY: 6 + (drawer.height-12-panelHeight)*ay
    function liquidRadius(w,h,p,finalRadius) {
        let capsule = Math.min(w,h)/2
        if (prefs.motionStyle !== "liquid") return Math.min(finalRadius,capsule)
        let t = smooth((p-0.20)/0.80)
        return Math.min(capsule,capsule*(1-t)+finalRadius*t)
    }
    // Anchor coordinates in the stable overlay: 0 = near edge, 0.5 = centre, 1 = far edge.
    property real ax: prefs.hotspot.indexOf("left") >= 0 ? 0 : prefs.hotspot.indexOf("right") >= 0 ? 1 : 0.5
    property real ay: prefs.hotspot.indexOf("top") >= 0 ? 0 : prefs.hotspot.indexOf("bottom") >= 0 ? 1 : 0.5
    property real panelWidth: Math.max(1, drawer.width - 12)
    property real panelHeight: Math.min(drawer.height - 12, animatedHeight)
    property bool rings: prefs.viewMode === "rings"
    onRingsChanged: if (opened) ringClock.jump(0)
    property color sessionColor: tone("primary", lightTheme ? "#222222" : "#e8e8e8")
    property color weeklyColor: tone("tertiary", lightTheme ? "#606060" : "#9b9b9b")
    function stagger(i) {
        if (prefs.motionStyle === "reduced") return root.opened ? 1 : 0
        let delay = prefs.staggerEnabled ? Math.min(0.58,Math.max(0,i)*0.09) : 0
        let start = 0.10 + delay
        return smooth((unit(drawerContentSpring.value)-start)/(1-start))
    }
    function windowFor(account, minutes) {
        let windows = account.windows || []
        return windows.find(w => Number(w.minutes) === minutes) || null
    }
    function remaining(w) {
        return w && w.remaining !== null && w.remaining !== undefined && isFinite(Number(w.remaining)) ? Math.max(0, Math.min(100, Number(w.remaining))) : -1
    }
    property bool settingsOpen: false
    Settings { id: prefs; location: "file:" + (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/aether/preferences.ini"; category: "AetherUI"; property bool followTheme: true; property bool hoverEnabled: true; property bool fullscreenOverride: false; property int motionMs: 240; property int dataMotionMs: 450; property int dismissDelay: 350; property int drawerWidth: 390; property int layoutWidth: 440; property int cacheSeconds: 5; property string viewMode: "grid"; property string hotspot: "top-right"; property bool staggerEnabled: true; property string hiddenProviders: "[]"; property string hiddenAccounts: "[]"; property string chartMode: "line"; property int hotspotSize: 40; property int hotspotRevision: 0; property string fontChoice: "auto"; property int cardRadius: 24; property string colorScheme: "mono"; property bool edgeFades: true; property int fadeDepth: 28; property bool localShortcutsEnabled: true; property bool globalShortcutsEnabled: true; property string shortcutBindings: "{}"; property string bindSyntax: "conf"; property string motionStyle: "liquid"; property bool autoUpdate: false; property string updateChannel: "stable"; property int motionRevision: 0; property real trackpadSpeed: 1.6; property bool wispMotion: true }
    property bool hyprlandAvailable: Hyprland.eventSocketPath.length > 0
    property bool activeFullscreen: false
    property bool fullscreenKnown: false
    property bool fullscreenRefreshPending: false
    property bool canOpenDrawer: prefs.fullscreenOverride || !hyprlandAvailable || (fullscreenKnown && !activeFullscreen)
    function scheduleFullscreenRefresh() { fullscreenRefresh.restart() }
    Timer { id: fullscreenRefresh; interval: 70; repeat: false; onTriggered: {
        if (!root.hyprlandAvailable) { root.activeFullscreen = false; root.fullscreenKnown = true; return }
        if (fullscreenReader.running) { root.fullscreenRefreshPending = true; return }
        fullscreenReader.running = true
    } }
    Process {
        id: fullscreenReader
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector { onStreamFinished: {
            try { root.activeFullscreen = Number(JSON.parse(text).fullscreen) > 0; root.fullscreenKnown = true }
            catch(e) { root.activeFullscreen = false; root.fullscreenKnown = false }
        } }
        onExited: if (root.fullscreenRefreshPending) { root.fullscreenRefreshPending = false; root.scheduleFullscreenRefresh() }
    }
    Connections {
        target: root.hyprlandAvailable ? Hyprland : null
        function onActiveToplevelChanged() { root.scheduleFullscreenRefresh() }
        function onRawEvent(event) {
            if (["fullscreen","activewindowv2","workspace","focusedmon","openwindow","closewindow"].includes(event.name)) root.scheduleFullscreenRefresh()
        }
    }
    onHyprlandAvailableChanged: if (hyprlandAvailable) scheduleFullscreenRefresh()
    onCanOpenDrawerChanged: if (!canOpenDrawer) hide()
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
    // Feather-derived 24 px paths (MIT); see FEATHER-LICENSE.
    function iconPath(name) {
        switch (name) {
        case "Overview": return "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z"
        case "Appearance": return "M4 7h16 M4 17h16 M9 4v6 M15 14v6"
        case "Providers": return "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2 M9 3a4 4 0 1 0 0 8a4 4 0 1 0 0-8 M22 21v-2a4 4 0 0 0-3-3.87 M16 3.13a4 4 0 0 1 0 7.75"
        case "Analytics": return "M3 3v18h18 M8 17v-4 M13 17V7 M18 17v-7"
        case "Behaviour": return "M4 6h16 M4 12h16 M4 18h16 M8 4v4 M16 10v4 M11 16v4"
        case "Shortcuts": return "M3 5h18v14H3z M7 9h.01 M11 9h.01 M15 9h.01 M7 13h.01 M11 13h.01 M15 13h.01 M8 16h8"
        case "Updates": return "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4 M7 10l5 5 5-5 M12 15V3"
        case "About": return "M12 22a10 10 0 1 0 0-20a10 10 0 0 0 0 20 M12 11v6 M12 7h.01"
        case "refresh": return "M20 11a8 8 0 0 0-14.9-3 M4 4v5h5 M4 13a8 8 0 0 0 14.9 3 M20 20v-5h-5"
        case "settings": return "M12 8a4 4 0 1 0 0 8a4 4 0 0 0 0-8 M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.6 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09a1.65 1.65 0 0 0 1.51-1.08 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.6a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"
        default: return ""
        }
    }
    component LineIcon: Item {
        id: icon
        property string name: ""
        property color ink: root.foreground
        implicitWidth: 18; implicitHeight: 18
        Shape {
            anchors.centerIn: parent; width: 24; height: 24
            scale: Math.min(icon.width, icon.height) / 24
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1.75; strokeColor: icon.ink; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathSvg { path: root.iconPath(icon.name) }
            }
        }
    }
    component HotspotGlyph: Item {
        id: glyph
        property string position: "top-left"
        property color ink: root.muted
        implicitWidth: 24; implicitHeight: 24
        Rectangle { x: 5; y: 5; width: 14; height: 11; radius: 2; color: "transparent"; border.width: 1.5; border.color: glyph.ink }
        Rectangle { x: 11; y: 16; width: 2; height: 3; color: glyph.ink }
        Rectangle { x: 8; y: 19; width: 8; height: 1.5; radius: 0.75; color: glyph.ink }
        Rectangle {
            width: 5; height: 5; radius: 2.5
            x: glyph.position.indexOf("left") >= 0 ? 2 : glyph.position.indexOf("right") >= 0 ? 17 : 9.5
            y: glyph.position.indexOf("top") >= 0 ? 2 : glyph.position.indexOf("bottom") >= 0 ? 14 : 8
            color: glyph.ink
        }
    }
    component HotspotChoice: Button {
        id: positionButton
        property string position: ""
        property bool selected: position !== "" && prefs.hotspot === position
        implicitWidth: 64; implicitHeight: 36
        enabled: position !== ""
        focusPolicy: Qt.StrongFocus; hoverEnabled: true
        checkable: true; autoExclusive: true; checked: selected
        Accessible.role: position === "" ? Accessible.StaticText : Accessible.RadioButton
        Accessible.name: position === "" ? "Screen" : "Activate from " + position.replace("center","centre").replace("-"," ")
        Accessible.checked: selected
        onClicked: if (position) prefs.hotspot = position
        background: Rectangle {
            radius: height/2
            color: positionButton.selected ? root.primary : positionButton.down || positionButton.hovered ? root.track : "transparent"
            border.width: positionButton.activeFocus ? 2 : 0; border.color: root.foreground
            Behavior on color { ColorAnimation { duration: root.controlDuration() } }
        }
        contentItem: Item {
            HotspotGlyph { anchors.centerIn: parent; visible: positionButton.position !== ""; position: positionButton.position; ink: positionButton.selected ? root.onAccent : root.muted }
            MText { anchors.centerIn: parent; visible: positionButton.position === ""; text: "SCREEN"; font.pixelSize: 11; color: root.muted }
        }
    }
    component MButton: Button {
        id: button
        property string glyph: "settings"
        implicitWidth: 44; implicitHeight: 44
        hoverEnabled: true; focusPolicy: Qt.StrongFocus
        Accessible.name: glyph === "refresh" ? "Refresh local view" : "Settings"
        contentItem: Item { LineIcon { anchors.centerIn: parent; width: 20; height: 20; name: button.glyph } }
        background: Rectangle {
            radius: button.down ? 14 : button.hovered ? 16 : 22
            color: button.hovered ? root.track : root.buttonColor
            border.width: button.activeFocus ? 2 : 0; border.color: root.primary
            Behavior on radius { NumberAnimation { duration: root.controlDuration(); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: root.controlDuration() } }
        }
        ToolTip.visible: hovered; ToolTip.text: Accessible.name; ToolTip.delay: 450
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
                MotionValue { id: switchSpring; targetValue: control.checked ? 1 : 0; factor: 0.4 }
                property real slide: root.unit(switchSpring.value)
                width: 16 + 4 * slide; height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: 6 + (parent.width - width - 10) * slide
                color: control.checked ? root.onAccent : root.muted
            }
            Behavior on color { ColorAnimation { duration: root.controlDuration() } }
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
            MotionValue { id: sliderSpring; targetValue: control.pressed ? 1.075 : 1; factor: 0.4 }
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
    function show() { if (!canOpenDrawer) return; closeTimer.stop(); if (!opened) { opened = true; ringClock.jump(0) } }
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
        function toggle(): void { if (root.settingsOpen) root.dismissAll(); else if (root.opened) root.hide(); else if (root.canOpenDrawer) { root.pinned = true; root.show() } }
        function isOpen(): bool { return root.opened }
        function canShow(): bool { return root.canOpenDrawer }
        function analytics(): void { root.openSettings("Analytics") }
        function refresh(): void { root.refreshView() }
        function dismiss(): void { root.dismissAll() }
        function shortcuts(): void { root.openSettings("Shortcuts") }
    }
    // Visual-only gradients, attached to the viewport rather than the moving
    // content item. Opacity tracks distance from each end, including short lists.
    // Use precise wheel deltas directly rather than queueing an animation for
    // each two-finger gesture. Handle mouse-classified precision input too.
    component PrecisionScroll: WheelHandler {
        required property Flickable viewport
        target: null
        acceptedDevices: PointerDevice.TouchPad | PointerDevice.Mouse
        orientation: Qt.Vertical
        blocking: true
        enabled: viewport.interactive && viewport.contentHeight > viewport.height
        onWheel: event => {
            let precise = event.pixelDelta.y !== 0
            let delta = precise ? event.pixelDelta.y * prefs.trackpadSpeed : event.angleDelta.y / 120 * 48
            if (delta === 0) return
            viewport.cancelFlick()
            let start = viewport.originY
            let end = start + Math.max(0, viewport.contentHeight - viewport.height)
            viewport.contentY = Math.max(start, Math.min(end, viewport.contentY - delta))
        }
    }
    // Monochrome vector trace of the approved spiral brand mark.
    // Original Wisp geometry; shared 18-second motion timing from docs/assets/branding.
    // Each visible instance has a local clock. Hidden instances stop entirely.
    component WispMark: Item {
        id: wisp
        implicitWidth: 28; implicitHeight: 28
        property bool animate: true
        property bool surfaceActive: root.settingsOpen
        property color ink: root.foreground
        property real phase: 0
        property bool moving: animate && visible && prefs.wispMotion && prefs.motionStyle !== "reduced" && surfaceActive
        readonly property var tracks: ({"drift":[[0,0],[18,0],[27,-3.4],[34,-1.5],[40,0],[63,0],[72,-3],[81,-1],[89,0],[100,0]],"sx":[[0,1],[19,1],[24,1.027],[28,0.975],[35,1.012],[39,1],[64,1],[69,1.02],[74,0.98],[82,1.008],[89,1],[100,1]],"sy":[[0,1],[19,1],[24,0.972],[28,1.035],[35,0.99],[39,1],[64,1],[69,0.98],[74,1.026],[82,0.993],[89,1],[100,1]],"blink":[[0,1],[11.9,1],[12.65,0.085],[13.05,0.085],[14,1],[33.9,1],[34.65,0.085],[35,0.085],[35.8,1],[54.2,1],[54.95,0.085],[55.35,0.085],[56.1,1],[85.2,1],[85.95,0.085],[86.35,0.085],[87.1,1],[100,1]],"curious":[[0,0],[43,0],[47,1],[51,1],[55,0],[100,0]],"happy":[[0,0],[67,0],[69,1],[78.8,1],[81,0],[100,0]],"glow":[[0,0],[24,0],[31,0.25],[41,0],[65,0],[74,0.42],[87,0],[100,0]]})
        function sample(points) {
            for (let i=1;i<points.length;i++) {
                if (phase <= points[i][0]) {
                    let t = root.smooth((phase-points[i-1][0])/(points[i][0]-points[i-1][0]))
                    return points[i-1][1] + (points[i][1]-points[i-1][1])*t
                }
            }
            return points[points.length-1][1]
        }
        function ellipse(x,y,rx,ry) {
            return "M"+x+" "+(y-ry)+"A"+rx+" "+ry+" 0 1 0 "+x+" "+(y+ry)+"A"+rx+" "+ry+" 0 1 0 "+x+" "+(y-ry)+"Z"
        }
        function smile(x) {
            return "M"+(x-4.6)+" 44.5Q"+x+" 36.8 "+(x+4.6)+" 44.5Q"+(x+5.8)+" 46.1 "+(x+3.1)+" 46.1Q"+x+" 40.7 "+(x-3.1)+" 46.1Q"+(x-5.8)+" 46.1 "+(x-4.6)+" 44.5Z"
        }
        readonly property real blink: sample(tracks.blink)
        readonly property real curious: sample(tracks.curious)
        readonly property real happy: sample(tracks.happy)
        readonly property real glow: sample(tracks.glow)
        readonly property string silhouette: "M48 10C68 10 82 25 82 43C82 57 75 65 64 71C58 74 54 78 53 86C47 82 44 77 44 71C35 79 24 77 17 69C10 60 11 47 15 35C20 20 32 10 48 10Z"
        readonly property string eyes: ellipse(35,43-.6*curious,5*(1+.08*curious),7*blink*(1+.12*curious)) + ellipse(57,43+.4*curious,5*(1-.05*curious),7*blink*(1-.22*curious))
        NumberAnimation on phase {
            running: wisp.moving; from: 0; to: 100; duration: 18000; loops: Animation.Infinite
        }
        onMovingChanged: if (!moving) phase = 0
        Item {
            anchors.centerIn: parent
            width: 96; height: 96
            scale: Math.min(wisp.width,wisp.height)/96
            Item {
                anchors.fill: parent
                transform: [
                    Translate { y: wisp.sample(wisp.tracks.drift) },
                    Scale { origin.x: 48; origin.y: 48; xScale: wisp.sample(wisp.tracks.sx); yScale: wisp.sample(wisp.tracks.sy) }
                ]
                // Subtle native halo approximation; no blur or compositor dependency.
                Shape {
                    anchors.fill: parent; scale: 1.09; opacity: wisp.glow*.22; visible: opacity>0
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath { strokeWidth: -1; fillColor: wisp.ink; PathSvg { path: wisp.silhouette } }
                }
                Shape {
                    anchors.fill: parent; opacity: 1-wisp.happy; visible: opacity>0
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath { strokeWidth: -1; fillColor: wisp.ink; fillRule: ShapePath.OddEvenFill; PathSvg { path: wisp.silhouette+wisp.eyes } }
                }
                Shape {
                    anchors.fill: parent; opacity: wisp.happy; visible: opacity>0
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath { strokeWidth: -1; fillColor: wisp.ink; fillRule: ShapePath.OddEvenFill; PathSvg { path: wisp.silhouette+wisp.smile(35)+wisp.smile(57) } }
                }
            }
        }
    }
    component ScrollFade: Item {
        id: edge
        required property Flickable viewport
        property color shade: root.surface
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
    // One stable overlay. The mask is the union of the hotspot and
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
        WlrLayershell.namespace: "aether-drawer"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: corner; Region { item: hitbox } }
        Item {
            id: corner
            x: (parent.width - width) * root.ax
            y: (parent.height - height) * root.ay
            width: prefs.hoverEnabled && !root.settingsOpen && root.canOpenDrawer ? prefs.hotspotSize : 0
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
                    if (!root.opened && prefs.hoverEnabled && !root.settingsOpen && root.canOpenDrawer) root.show()
                } else if (root.opened && !root.pinned) closeTimer.restart()
            }
        }
        Rectangle {
            id: body
            property real seed: Math.max(1,Math.min(prefs.hotspotSize,root.panelWidth,root.panelHeight))
            x: 6 + (drawer.width - 12 - width) * root.ax
            y: 6 + (drawer.height - 12 - height) * root.ay
            width: seed + (root.panelWidth - seed) * root.reveal
            height: seed + (root.panelHeight - seed) * root.reveal
            visible: root.opened || root.reveal > 0.0001
            enabled: root.opened
            radius: root.liquidRadius(width,height,root.reveal,30)
            color: root.surface

            clip: true
            // The content is always measured at the FINAL width. No text
            // reflow, scale, or layout resizing during the reveal.
            Flickable {
                id: scroll
                x: root.finalPanelX + 22 - body.x
                y: root.finalPanelY + 22 - body.y
                width: Math.max(1, drawer.width - 56)
                height: Math.max(1, root.panelHeight - 44)
                enabled: root.opened && root.reveal > 0.75
                interactive: enabled && contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                synchronousDrag: true
                maximumFlickVelocity: 3500
                PrecisionScroll { viewport: scroll }
                contentWidth: width; contentHeight: content.implicitHeight
                clip: true
                ColumnLayout {
                    id: content
                    width: scroll.width; spacing: 16
                    RowLayout {
                        id: heading
                        opacity: root.stagger(0)
                        transform: Translate { y: (1 - heading.opacity) * 4 }
                        Layout.fillWidth: true; spacing: 12
                        WispMark { Layout.preferredWidth: 38; Layout.preferredHeight: 38; surfaceActive: root.opened }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 4
                            MText { text: "aether.ai"; font.pixelSize: 32; font.weight: Font.DemiBold; font.letterSpacing: -1.3; Layout.fillWidth: true; elide: Text.ElideRight }
                            MText { text: "AI resource monitor"; color: root.muted; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                        MButton { glyph: "refresh"; Layout.alignment: Qt.AlignVCenter; onClicked: root.refreshView() }
                        MButton { Layout.alignment: Qt.AlignVCenter; onClicked: { root.settingsOpen = true; root.hide() } }
                    }
                    RowLayout {
                        id: sectionHeading
                        opacity: root.stagger(1)
                        transform: Translate { y: (1 - sectionHeading.opacity) * 4 }
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
                            transform: Translate { y: (1 - accountCard.opacity) * 4 }
                            Layout.fillWidth: true
                            implicitHeight: card.implicitHeight + 36
                            radius: prefs.cardRadius; color: root.cardColor
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
                                MText { visible: accountCard.modelData.authKind === "api_key"; text: "API key · quota resources unavailable"; color: root.muted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                MText { visible: accountCard.modelData.status !== "ok" && accountCard.modelData.authKind !== "api_key"; text: accountCard.modelData.status; color: root.danger; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                Repeater {
                                    model: accountCard.modelData.authKind === "api_key" ? [] : accountCard.modelData.windows || []
                                    delegate: ColumnLayout {
                                        required property var modelData
                                        id: quota
                                        property bool known: modelData.remaining !== null && modelData.remaining !== undefined && isFinite(Number(modelData.remaining))
                                        property real remaining: known ? Math.max(0, Math.min(100, Number(modelData.remaining))) : 0
                                        property color indicator: known && remaining < 20 ? root.danger : root.primary
                                        required property int index
                                        opacity: root.stagger(accountCard.index + 3 + index)
                                        transform: Translate { y: (1 - quota.opacity) * 4 }
                                        Layout.fillWidth: true; spacing: 8
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            MText { text: quota.modelData.minutes === 10080 ? "Weekly" : quota.modelData.minutes === 300 ? "5-hour session" : quota.modelData.minutes ? (quota.modelData.minutes / 60) + "h window" : "Quota"; font.pixelSize: 13; font.weight: Font.Medium; Layout.fillWidth: true }
                                            MText { text: quota.known ? Math.round(quota.remaining) + "%" : "—"; color: quota.indicator; font.family: root.monoFont; font.pixelSize: 19; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignRight }
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true; implicitHeight: 8; radius: 4; color: root.track
                                            Rectangle { property real displayedQuota: quota.remaining; Behavior on displayedQuota { NumberAnimation { duration: root.dataDuration(0.90); easing.type: Easing.Linear } } width: parent.width * displayedQuota / 100 * root.ringProgress(accountCard.index); height: parent.height; radius: Math.min(4, width / 2); color: quota.indicator }
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
                            model: root.rings ? root.ringAccountIds : []
                            delegate: Rectangle {
                                id: ringCard
                                required property var modelData
                                required property int index
                                property var account: root.accounts.find(a => String(a.id) === String(modelData)) || ({name:"",provider:"",windows:[],status:"ok"})
                                property bool apiKey: account.authKind === "api_key"
                                property var session: root.windowFor(account, 300)
                                property var week: root.windowFor(account, 10080)
                                property real sessionLeft: root.remaining(session)
                                property real weekLeft: root.remaining(week)
                                property real sessionSweep: Math.max(0, sessionLeft)
                                property real weekSweep: Math.max(0, weekLeft)
                                Behavior on sessionSweep { enabled: root.opened && prefs.motionStyle !== "reduced"; NumberAnimation { duration: root.dataDuration(0.90); easing.type: Easing.Linear } }
                                Behavior on weekSweep { enabled: root.opened && prefs.motionStyle !== "reduced"; NumberAnimation { duration: root.dataDuration(0.90); easing.type: Easing.Linear } }
                                Layout.fillWidth: true
                                Layout.minimumWidth: 100
                                Layout.preferredWidth: 144
                                implicitHeight: ringContent.implicitHeight + 24
                                radius: prefs.cardRadius; color: root.cardColor
                                opacity: root.stagger(index + 2)
                                transform: Translate { y: (1 - ringCard.opacity) * 4 }
                                ColumnLayout {
                                    id: ringContent
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                    anchors.margins: 12; spacing: 5
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        ProviderIcon { Layout.preferredWidth: 23; Layout.preferredHeight: 23; name: root.logo(ringCard.account.provider); fallback: String(ringCard.account.provider).slice(0,1).toUpperCase() }
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                                            MText { Layout.fillWidth: true; elide: Text.ElideRight; text: ringCard.account.name; font.weight: Font.DemiBold; font.pixelSize: 12 }
                                            MText { Layout.fillWidth: true; elide: Text.ElideRight; text: ringCard.account.provider; color: root.muted; font.pixelSize: 10 }
                                        }
                                    }
                                    Item {
                                        id: ringFace
                                        visible: !ringCard.apiKey
                                        // Never let the layout independently stretch the two axes.
                                        property real diameter: Math.max(1, Math.min(root.accounts.length === 1 ? 144 : 132, Math.floor(ringCard.width - 24)))
                                        property real strokeSize: diameter * 0.05
                                        property real outerRadius: diameter * 0.40
                                        property real innerRadius: diameter * (37 / 120)
                                        property real drawProgress: root.ringProgress(ringCard.index)
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
                                                fillColor: "transparent"; strokeColor: root.track
                                                strokeWidth: ringFace.strokeSize; capStyle: ShapePath.RoundCap
                                                PathAngleArc { centerX: ringFace.diameter/2; centerY: ringFace.diameter/2; radiusX: ringFace.outerRadius; radiusY: ringFace.outerRadius; startAngle: 270; sweepAngle: 360 }
                                            }
                                            ShapePath {
                                                fillColor: "transparent"; strokeColor: root.track
                                                strokeWidth: ringFace.strokeSize; capStyle: ShapePath.RoundCap
                                                PathAngleArc { centerX: ringFace.diameter/2; centerY: ringFace.diameter/2; radiusX: ringFace.innerRadius; radiusY: ringFace.innerRadius; startAngle: 270; sweepAngle: 360 }
                                            }
                                            ShapePath {
                                                fillColor: "transparent"; strokeColor: ringCard.sessionSweep > 0 && ringFace.drawProgress > 0 ? root.sessionColor : "transparent"
                                                strokeWidth: ringFace.strokeSize; capStyle: ShapePath.RoundCap
                                                PathAngleArc { centerX: ringFace.diameter/2; centerY: ringFace.diameter/2; radiusX: ringFace.outerRadius; radiusY: ringFace.outerRadius; startAngle: 270; sweepAngle: 3.6 * ringCard.sessionSweep * ringFace.drawProgress }
                                            }
                                            ShapePath {
                                                fillColor: "transparent"; strokeColor: ringCard.weekSweep > 0 && ringFace.drawProgress > 0 ? root.weeklyColor : "transparent"
                                                strokeWidth: ringFace.strokeSize; capStyle: ShapePath.RoundCap
                                                PathAngleArc { centerX: ringFace.diameter/2; centerY: ringFace.diameter/2; radiusX: ringFace.innerRadius; radiusY: ringFace.innerRadius; startAngle: 270; sweepAngle: 3.6 * ringCard.weekSweep * ringFace.drawProgress }
                                            }
                                        }
                                        // Fit both lines inside the inner circle, including 100%,
                                        // wide user-selected fonts and narrow multi-account cards.
                                        Column {
                                            anchors.centerIn: parent
                                            width: Math.floor(ringFace.diameter * 0.43)
                                            spacing: Math.max(1, Math.round(ringFace.diameter * 0.012))
                                            MText {
                                                width: parent.width; height: Math.max(1, Math.floor(ringFace.diameter * 0.19))
                                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                                text: ringCard.sessionLeft < 0 ? "—" : Math.round(ringCard.sessionLeft) + "%"
                                                font.weight: Font.DemiBold
                                                font.pixelSize: Math.max(6, Math.floor(ringFace.diameter * 0.17))
                                                minimumPixelSize: 4; fontSizeMode: Text.Fit
                                                wrapMode: Text.NoWrap; color: root.foreground
                                            }
                                            MText {
                                                width: parent.width; height: Math.max(1, Math.floor(ringFace.diameter * 0.105))
                                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                                text: "session"; font.pixelSize: Math.max(6, Math.floor(ringFace.diameter * 0.078))
                                                minimumPixelSize: 4; fontSizeMode: Text.Fit; wrapMode: Text.NoWrap; color: root.muted
                                            }
                                        }
                                    }
                                    ColumnLayout {
                                        visible: ringCard.apiKey
                                        Layout.fillWidth: true; spacing: 6
                                        Rectangle {
                                            Layout.fillWidth: true; implicitHeight: 42; radius: 12
                                            color: root.track
                                            MText { anchors.centerIn: parent; text: "API KEY"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.foreground }
                                        }
                                        MText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: "Quota resources unavailable"; color: root.muted; font.pixelSize: 10; wrapMode: Text.WordWrap }
                                    }

                                    // Align labels and values with the product reference; keep
                                    // reset text subordinate rather than splitting it into a third row.
                                    Repeater {
                                        model: ringCard.apiKey ? [] : [
                                            { label: "Session", value: ringCard.sessionLeft, quota: ringCard.session, tint: root.sessionColor },
                                            { label: "Weekly", value: ringCard.weekLeft, quota: ringCard.week, tint: root.weeklyColor }
                                        ]
                                        delegate: RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true; spacing: 6
                                            ColumnLayout {
                                                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                                MText { Layout.fillWidth: true; text: modelData.label; color: root.muted; font.pixelSize: 11; elide: Text.ElideRight }
                                                MText {
                                                    visible: modelData.quota !== null
                                                    Layout.fillWidth: true; font.pixelSize: 10; color: root.muted; elide: Text.ElideRight
                                                    text: root.resetText(modelData.quota ? modelData.quota.reset : null)
                                                }
                                            }
                                            MText {
                                                text: modelData.value < 0 ? "—" : Math.round(modelData.value) + "%"
                                                color: modelData.tint; font.family: root.monoFont; font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                    MText { visible: ringCard.account.status !== "ok" && !ringCard.apiKey; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: root.danger; font.pixelSize: 11; text: ringCard.account.status }
                                }
                            }
                        }
                    }
                    RowLayout {
                        id: footer
                        opacity: root.stagger(Math.min(root.accounts.length + 3, 10))
                        transform: Translate { y: (1 - footer.opacity) * 4 }
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
        MotionValue { id: buttonSpring; targetValue: choiceMouse.pressed ? 0.98 : 1; factor: 0.4 }
        Rectangle {
            anchors.fill: parent; radius: choice.radius
            scale: prefs.motionStyle === "liquid" ? buttonSpring.value : 1
            color: choice.selected ? root.primary : choiceMouse.pressed ? root.buttonColor : choiceMouse.containsMouse ? (choice.elevated ? root.buttonColor : root.track) : choice.elevated ? root.track : root.cardColor
            border.width: choice.elevated && !choice.selected ? 1 : 0
            border.color: choiceMouse.containsMouse ? root.primary : root.outline
            Behavior on color { ColorAnimation { duration: root.controlDuration() } }
            Behavior on border.color { ColorAnimation { duration: root.controlDuration() } }
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
            Behavior on color { ColorAnimation { duration: root.controlDuration() } }
            Behavior on border.color { ColorAnimation { duration: root.controlDuration() } }
        }
        indicator: ChevronDown {
            width: 19; height: 19
            x: liquidSelect.width-width-14; y: (liquidSelect.height-height)/2
            ink: liquidSelect.enabled ? root.foreground : root.muted
            rotation: liquidPopup.visible ? (liquidPopup.above ? 0 : 180) : (liquidSelect.prefersAbove ? 180 : 0)
            transformOrigin: Item.Center
            Behavior on rotation { NumberAnimation { duration: root.motionDuration(0.55); easing.type: Easing.InOutCubic } }
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
                Behavior on color { ColorAnimation { duration: root.controlDuration() } }
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
            property real shownContent: root.smooth((growth-0.12)/0.72)
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
                        PrecisionScroll { viewport: liquidGrid }
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                }
            }
            enter: Transition {
                NumberAnimation { target: liquidPopup; property: "growth"; to: 1; duration: root.motionDuration(0.72); easing.type: Easing.InOutSine }
            }
            exit: Transition {
                NumberAnimation { target: liquidPopup; property: "growth"; to: 0; duration: root.motionDuration(0.56); easing.type: Easing.InOutSine }
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
        radius: 20; color: root.cardColor
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
        Behavior on color { ColorAnimation { duration: root.controlDuration() } }
        RowLayout { anchors.fill: parent; anchors.margins: 14
            GitHubMark { visible: link.githubIcon; Layout.preferredWidth: 18; Layout.preferredHeight: 18; ink: root.foreground }
            MText { text: link.label; Layout.fillWidth: true; font.weight: Font.Medium }
            MText { visible: !link.githubIcon; text: "↗"; color: root.muted }
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
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "aether-settings"
        WlrLayershell.keyboardFocus: root.settingsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        Rectangle {
            id: settingsBody
            anchors.centerIn: parent
            width: settingsPanel.width
            height: settingsPanel.height
            scale: 0.985 + 0.015*root.settingsReveal
            transformOrigin: Item.TopRight
            radius: 30; color: root.surface

            clip: true
            opacity: root.settingsReveal
            visible: root.settingsReveal > 0.0001
            enabled: root.settingsOpen
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
                opacity: root.smooth((settingsContentSpring.value-0.12)/0.68)
                enabled: root.settingsOpen && opacity > 0.65
                spacing: 0
                Rectangle {
                    Layout.preferredWidth: settingsPanel.width < 680 ? 126 : 216
                    Layout.fillHeight: true
                    color: root.cardColor; radius: 24
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; spacing: 8
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            WispMark { Layout.preferredWidth: 28; Layout.preferredHeight: 28; animate: root.settingsTab !== "About" }
                            MText { text: "aether.ai"; font.pixelSize: settingsPanel.width < 680 ? 16 : 26; font.weight: Font.DemiBold; font.letterSpacing: -0.9; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                        Description { text: "Control centre"; font.pixelSize: 11 }
                        Item { Layout.preferredHeight: 12 }
                        Item {
                            id: navigationTrack
                            property real rowHeight: Math.max(28, Math.min(44, (settingsPanel.height-190)/root.settingsPages.length-8))
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.settingsPages.length * (rowHeight+8)-8
                            MotionValue { id: navSpring; targetValue: Math.max(0,root.settingsPages.indexOf(root.settingsTab))*(navigationTrack.rowHeight+8); factor: 0.55 }
                            Rectangle {
                                width: parent.width; height: navigationTrack.rowHeight; radius: height/2
                                y: Math.max(0,Math.min(parent.height-height,navSpring.value))
                                color: root.primary
                            }
                            Column {
                                anchors.fill: parent; spacing: 8
                                Repeater {
                                    model: root.settingsPages
                                    delegate: Button {
                                        id: navigationButton
                                        required property string modelData
                                        width: navigationTrack.width; height: navigationTrack.rowHeight
                                        leftPadding: 14; rightPadding: 14
                                        hoverEnabled: true; focusPolicy: Qt.StrongFocus
                                        Accessible.name: modelData
                                        onClicked: root.selectPage(modelData)
                                        background: Rectangle {
                                            radius: height/2
                                            color: root.settingsTab !== navigationButton.modelData && navigationButton.hovered ? root.track : "transparent"
                                            border.width: navigationButton.activeFocus ? 2 : 0; border.color: root.foreground
                                        }
                                        contentItem: RowLayout {
                                            spacing: 8
                                            LineIcon { name: navigationButton.modelData; visible: settingsPanel.width >= 680; Layout.preferredWidth: 16; Layout.preferredHeight: 16; ink: root.settingsTab === navigationButton.modelData ? root.onAccent : root.foreground }
                                            MText { text: navigationButton.modelData; color: root.settingsTab === navigationButton.modelData ? root.onAccent : root.foreground; font.weight: Font.Medium; font.pixelSize: 13; Layout.fillWidth: true }
                                        }
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                        Description { text: "MIT · v" + root.version; font.pixelSize: 11 }
                        Choice { label: "GitHub"; githubIcon: true; Layout.fillWidth: true; onChosen: Qt.openUrlExternally("https://github.com/maynkudu/aether-ai") }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 18; spacing: 16
                    RowLayout {
                        Layout.fillWidth: true
                        Item {
                            id: pageHeading
                            Layout.fillWidth: true; implicitHeight: headingLabel.implicitHeight
                            MText {
                                id: headingLabel; text: root.settingsTab; width: pageHeading.width
                                font.pixelSize: 31; font.weight: Font.DemiBold; font.letterSpacing: -1; elide: Text.ElideRight
                                opacity: root.pageStage(0)
                                transform: ItemGrowth { stage: root.pageStage(0) }
                            }
                        }
                        Choice { label: "Done"; onChosen: root.settingsOpen = false }
                    }
                    Item {
                        id: pageViewport
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Flickable {
                        id: pageScroll
                        anchors.fill: pageViewport
                        clip: true; contentWidth: width; contentHeight: page.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick
                        synchronousDrag: true
                        maximumFlickVelocity: 3500
                        PrecisionScroll { viewport: pageScroll; enabled: !root.activeDropdown && viewport.interactive && viewport.contentHeight > viewport.height }
                        ColumnLayout {
                            id: page
                            width: pageScroll.width; spacing: 16
                            ColumnLayout {
                                visible: root.settingsTab === "Overview"; Layout.fillWidth: true; spacing: 14
                                Description { opacity: root.pageStage(1); transform: ItemGrowth { stage: root.pageStage(1) }
                                    text: "Your AI resources, in one place. All data stays on this device." }
                                GridLayout {
                                    
                                    columns: 2; Layout.fillWidth: true; columnSpacing: 12; rowSpacing: 12
                                    StatCard { opacity: root.pageStage(2); transform: ItemGrowth { stage: root.pageStage(2) } label: "Visible accounts"; value: String(root.accounts.length) }
                                    StatCard { opacity: root.pageStage(3); transform: ItemGrowth { stage: root.pageStage(3) } label: "Healthy accounts"; value: String(root.accounts.filter(a => a.status === "ok").length) }
                                    StatCard { opacity: root.pageStage(4); transform: ItemGrowth { stage: root.pageStage(4) } label: "Providers"; value: String(new Set(root.accounts.map(a => a.provider)).size) }
                                    StatCard { opacity: root.pageStage(5); transform: ItemGrowth { stage: root.pageStage(5) } label: "Token requests"; value: root.countText(root.analyticsTotals.requests) }
                                }
                                SectionTitle { opacity: root.pageStage(6); transform: ItemGrowth { stage: root.pageStage(6) }
                                    text: "Current provider data" }
                                Description { opacity: root.pageStage(7); transform: ItemGrowth { stage: root.pageStage(7) }
                                    text: root.status }
                                Repeater {
                                    model: root.accounts
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        opacity: root.pageStage(index+8); transform: ItemGrowth { stage: root.pageStage(index+8) }
                                        id: overviewAccount
                                        Layout.fillWidth: true; implicitHeight: overviewDetails.implicitHeight+28; radius: 18; color: root.cardColor
                                        ColumnLayout {
                                            id: overviewDetails
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14; spacing: 12
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 12
                                                ProviderIcon { Layout.preferredWidth: 32; Layout.preferredHeight: 32; name: root.logo(overviewAccount.modelData.provider); fallback: String(overviewAccount.modelData.provider).slice(0,1).toUpperCase() }
                                                ColumnLayout { Layout.fillWidth: true; spacing: 3
                                                    MText { text: overviewAccount.modelData.provider + " · " + overviewAccount.modelData.name; Layout.fillWidth: true; elide: Text.ElideRight; font.weight: Font.Medium }
                                                    Description { text: overviewAccount.modelData.authKind === "api_key" ? "API key · quota resources unavailable" : overviewAccount.modelData.status; font.pixelSize: 11 }
                                                }
                                            }
                                            RowLayout {
                                                visible: overviewAccount.modelData.authKind !== "api_key"
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
                                                            Rectangle { width: parent.width*Math.max(0,overviewQuota.modelData.value)/100*root.pageDataProgress(overviewAccount.index+overviewQuota.index); height: parent.height; radius: 3; color: overviewQuota.modelData.tint }
                                                        }
                                                    }
                                                }
                                            }
                                            Description { visible: overviewAccount.modelData.authKind === "api_key"; text: "API-key usage is shown in Analytics. Quota resources are unavailable."; font.pixelSize: 11 }
                                        }
                                    }
                                }
                                Description { opacity: root.pageStage(11); transform: ItemGrowth { stage: root.pageStage(11) }
                                    visible: root.accounts.length === 0; text: "No visible accounts. Check provider preferences or run aether refresh." }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Appearance"; Layout.fillWidth: true; spacing: 14
                                SectionTitle { opacity: root.pageStage(1); transform: ItemGrowth { stage: root.pageStage(1) }
                                    text: "Dashboard" }
                                RowLayout { opacity: root.pageStage(2); transform: ItemGrowth { stage: root.pageStage(2) }
                                    Layout.fillWidth: true
                                    MText { text: "Layout"; Layout.fillWidth: true }
                                    LiquidSelect { Layout.preferredWidth: 180; model: ["Grid","Rings"]; currentIndex: prefs.viewMode === "rings" ? 1 : 0; onActivated: function(index) { prefs.viewMode = index === 1 ? "rings" : "grid" }}
                                }
                                SectionTitle { opacity: root.pageStage(3); transform: ItemGrowth { stage: root.pageStage(3) }
                                    text: "Colour scheme" }
                                Description { opacity: root.pageStage(4); transform: ItemGrowth { stage: root.pageStage(4) }
                                    text: "Choose a built-in palette or follow Caelestia. Mono is the default." }
                                RowLayout { opacity: root.pageStage(5); transform: ItemGrowth { stage: root.pageStage(5) }
                                    
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
                                        onActivated: function(index) { if (unavailableReason(index)) { currentIndex = Math.max(0,root.schemeChoices.findIndex(x => x.id === prefs.colorScheme)); return } prefs.colorScheme = root.schemeChoices[index].id }
                                    }
                                }
                                Description { opacity: root.pageStage(6); transform: ItemGrowth { stage: root.pageStage(6) }
                                    visible: !root.caelestiaAvailable; text: prefs.colorScheme === "caelestia" ? "Caelestia unavailable · using Mono. " + root.caelestiaReason : "Caelestia unavailable · requires a running shell and palette." }
                                RowLayout { opacity: root.pageStage(7); transform: ItemGrowth { stage: root.pageStage(7) }
                                    MText { text: "Drawer width · " + prefs.layoutWidth + " px"; Layout.fillWidth: true } MSlider { from: 360; to: 560; stepSize: 10; value: prefs.layoutWidth; onMoved: prefs.layoutWidth = Math.round(value) } }
                                RowLayout { opacity: root.pageStage(8); transform: ItemGrowth { stage: root.pageStage(8) }
                                    MText { text: "Card rounding · " + prefs.cardRadius + " px"; Layout.fillWidth: true } MSlider { from: 8; to: 32; stepSize: 2; value: prefs.cardRadius; onMoved: prefs.cardRadius = Math.round(value) } }
                                SectionTitle { opacity: root.pageStage(9); transform: ItemGrowth { stage: root.pageStage(9) }
                                    text: "Typography" }
                                Description { opacity: root.pageStage(10); transform: ItemGrowth { stage: root.pageStage(10) }
                                    text: "Choose the UI typeface. The dropdown lists installed families and the preview updates immediately." }
                                Rectangle { opacity: root.pageStage(11); transform: ItemGrowth { stage: root.pageStage(11) }
                                    
                                    Layout.fillWidth: true; implicitHeight: 94; radius: 20; color: root.cardColor
                                    ColumnLayout { anchors.fill: parent; anchors.margins: 16; spacing: 4
                                        MText { text: "Intelligence, within limits."; font.pixelSize: 24; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                        Description { text: root.sans + " · Aa Bb Cc 0123456789"; font.pixelSize: 12 }
                                    }
                                }
                                LiquidSelect { opacity: root.pageStage(12); transform: ItemGrowth { stage: root.pageStage(12) }
                                    
                                    id: fontSelector
                                    Layout.fillWidth: true; fontPreview: true
                                    model: ["auto","Inter","Manrope","Montserrat","Poppins","DM Sans","Plus Jakarta Sans","Space Grotesk","Outfit","Sora","Figtree","Rubik","Noto Sans"].filter(n => n === "auto" || root.installedFonts.includes(n))
                                    labelFor: function(n) { return n === "auto" ? "Automatic" : n }
                                    currentIndex: Math.max(0,model.indexOf(prefs.fontChoice))
                                    onActivated: function(index) { prefs.fontChoice = model[index] }
                                }
                                Description { opacity: root.pageStage(13); transform: ItemGrowth { stage: root.pageStage(13) }
                                    text: "Install the curated font pack with bash install.sh --ui-only --fetch-fonts from the repository, then restart aether." }
                                SectionTitle { opacity: root.pageStage(14); transform: ItemGrowth { stage: root.pageStage(14) }
                                    text: "Scrolling" }
                                RowLayout { opacity: root.pageStage(15); transform: ItemGrowth { stage: root.pageStage(15) } MText { text: "Trackpad speed · " + prefs.trackpadSpeed.toFixed(1) + "×"; Layout.fillWidth: true } MSlider { from: 0.8; to: 3.0; stepSize: 0.1; value: prefs.trackpadSpeed; onMoved: prefs.trackpadSpeed = Math.round(value*10)/10 } }
                                RowLayout { opacity: root.pageStage(16); transform: ItemGrowth { stage: root.pageStage(16) }
                                    MText { text: "Scroll edge fades"; Layout.fillWidth: true } MSwitch { checked: prefs.edgeFades; onToggled: prefs.edgeFades = checked } }
                                RowLayout { opacity: root.pageStage(17); transform: ItemGrowth { stage: root.pageStage(17) }
                                    MText { text: "Fade depth · " + prefs.fadeDepth + " px"; Layout.fillWidth: true } MSlider { enabled: prefs.edgeFades; from: 12; to: 48; stepSize: 2; value: prefs.fadeDepth; onMoved: prefs.fadeDepth = Math.round(value) } }
                                SectionTitle { opacity: root.pageStage(18); transform: ItemGrowth { stage: root.pageStage(18) }
                                    text: "Motion" }
                                Description { opacity: root.pageStage(19); transform: ItemGrowth { stage: root.pageStage(19) }
                                    text: "Liquid uses responsive, interruptible transitions with capsule-shaped surfaces. Smooth is slightly slower. Data fills have independent timing; Reduced disables both." }
                                RowLayout { opacity: root.pageStage(20); transform: ItemGrowth { stage: root.pageStage(20) }
                                    
                                    Layout.fillWidth: true
                                    MText { text: "Motion style"; Layout.fillWidth: true }
                                    LiquidSelect { Layout.preferredWidth: 180; model: ["Liquid","Smooth","Reduced"]; currentIndex: Math.max(0,["liquid","smooth","reduced"].indexOf(prefs.motionStyle)); onActivated: function(index) { prefs.motionStyle = ["liquid","smooth","reduced"][index] }}
                                }
                                RowLayout { opacity: root.pageStage(21); transform: ItemGrowth { stage: root.pageStage(21) } MText { text: "Animate Wisp"; Layout.fillWidth: true } MSwitch { checked: prefs.wispMotion; enabled: prefs.motionStyle !== "reduced"; onToggled: prefs.wispMotion = checked } }
                                Description { opacity: root.pageStage(22); transform: ItemGrowth { stage: root.pageStage(22) } text: "Wisp is aether.ai’s mascot. Reduced motion keeps Wisp still." }
                                RowLayout { opacity: root.pageStage(23); transform: ItemGrowth { stage: root.pageStage(23) }
                                    MText { text: "Stagger content reveal"; Layout.fillWidth: true } MSwitch { checked: prefs.staggerEnabled; onToggled: prefs.staggerEnabled = checked } }
                                RowLayout { opacity: root.pageStage(24); transform: ItemGrowth { stage: root.pageStage(24) }
                                    MText { text: "Interface motion · " + prefs.motionMs + " ms"; Layout.fillWidth: true } MSlider { from: 120; to: 1200; stepSize: 20; value: prefs.motionMs; onMoved: prefs.motionMs = Math.round(value) } }
                                RowLayout { opacity: root.pageStage(25); transform: ItemGrowth { stage: root.pageStage(25) } MText { text: "Data motion · " + prefs.dataMotionMs + " ms"; Layout.fillWidth: true } MSlider { from: 200; to: 2800; stepSize: 100; value: prefs.dataMotionMs; onMoved: prefs.dataMotionMs = Math.round(value) } }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Providers"; Layout.fillWidth: true; spacing: 12
                                Description { opacity: root.pageStage(1); transform: ItemGrowth { stage: root.pageStage(1) }
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
                                        opacity: root.pageStage(index+2); transform: ItemGrowth { stage: root.pageStage(index+2) }
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
                                                    required property int index
                                                    required property var modelData
                                                    property bool shown: !root.hiddenAccounts.includes(String(modelData.id))
                                                    property real session: root.remaining(root.windowFor(modelData,300))
                                                    property real weekly: root.remaining(root.windowFor(modelData,10080))
                                                    Layout.fillWidth: true; implicitHeight: accountDetails.implicitHeight + 24
                                                    radius: 16; color: root.surface; border.width: 1; border.color: root.outline
                                                    opacity: (providerRow.shown ? 1 : 0.55)*root.pageStage(providerRow.index+3+index)
                                                    transform: ItemGrowth { stage: root.pageStage(providerRow.index+3+index) }
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
                                                                    MText { text: !accountRow.shown || !providerRow.shown ? "Hidden" : accountRow.modelData.authKind === "api_key" ? "API key · resources unavailable" : accountRow.modelData.status === "ok" ? "Available" : accountRow.modelData.status === "stale" ? "Stale cache" : "Unavailable"; font.pixelSize: 11; color: root.muted }
                                                                }
                                                            }
                                                            MSwitch { enabled: providerRow.shown; checked: accountRow.shown; onToggled: root.setHidden("hiddenAccounts", String(accountRow.modelData.id), !checked) }
                                                        }
                                                        RowLayout {
                                                            visible: accountRow.modelData.authKind !== "api_key"
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
                                                                        Rectangle { width: parent.width * Math.max(0,miniQuota.modelData.value) / 100 * root.pageDataProgress(0); height: parent.height; radius: 2; color: miniQuota.modelData.tint }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                        Description { visible: accountRow.modelData.authKind === "api_key"; text: "Quota resources are unavailable for API-key sessions."; font.pixelSize: 11 }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Analytics"; Layout.fillWidth: true; spacing: 14
                                Description { opacity: root.pageStage(1); transform: ItemGrowth { stage: root.pageStage(1) }
                                    text: "Token usage comes from local Codex session logs. Cost is an API-equivalent estimate using standard OpenAI rates, not your provider invoice." }
                                Flow {
                                    Layout.fillWidth: true; spacing: 8
                                    Repeater { model: [{v:"1",n:"24 hours"},{v:"7",n:"7 days"},{v:"30",n:"30 days"},{v:"90",n:"90 days"}]
                                        delegate: Choice { required property var modelData; required property int index; opacity: root.pageStage(2+index); transform: ItemGrowth { stage: root.pageStage(2+index) } label: modelData.n; selected: root.analyticsPeriod === modelData.v; onChosen: root.analyticsPeriod = modelData.v }
                                    }
                                }
                                RowLayout { opacity: root.pageStage(3); transform: ItemGrowth { stage: root.pageStage(3) }
                                    Layout.fillWidth: true
                                    Choice { label: "Tokens"; selected: root.analyticsMetric === "tokens"; onChosen: root.analyticsMetric = "tokens" }
                                    Choice { label: "Cost estimate"; selected: root.analyticsMetric === "cost"; onChosen: root.analyticsMetric = "cost" }
                                    Item { Layout.fillWidth: true }
                                    Choice { label: "Line"; selected: prefs.chartMode === "line"; onChosen: { if (prefs.chartMode !== "line") { prefs.chartMode = "line"; pageDataClock.jump(0) } } }
                                    Choice { label: "Bars"; selected: prefs.chartMode === "bars"; onChosen: { if (prefs.chartMode !== "bars") { prefs.chartMode = "bars"; pageDataClock.jump(0) } } }
                                }
                                GridLayout {
                                    columns: 2; Layout.fillWidth: true; columnSpacing: 12; rowSpacing: 12
                                    StatCard { opacity: root.pageStage(4); transform: ItemGrowth { stage: root.pageStage(4) } label: "Estimated API cost"; value: root.analyticsTotals.requests && root.analyticsTotals.costComplete ? root.costText(root.analyticsTotals.cost) : "—" }
                                    StatCard { opacity: root.pageStage(5); transform: ItemGrowth { stage: root.pageStage(5) } label: "Input tokens"; value: root.countText(root.analyticsTotals.input) }
                                    StatCard { opacity: root.pageStage(6); transform: ItemGrowth { stage: root.pageStage(6) } label: "Output tokens"; value: root.countText(root.analyticsTotals.output) }
                                    StatCard { opacity: root.pageStage(7); transform: ItemGrowth { stage: root.pageStage(7) } label: "Requests"; value: root.countText(root.analyticsTotals.requests) }
                                }
                                Flow { Layout.fillWidth: true; spacing: 14
                                    Repeater {
                                        model: root.analyticsProviders
                                        delegate: RowLayout {
                                            required property string modelData
                                            spacing: 6
                                            Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: root.providerColor(modelData) }
                                            MText { text: modelData; color: root.muted; font.pixelSize: 11 }
                                        }
                                    }
                                }
                                Description { opacity: root.pageStage(8); transform: ItemGrowth { stage: root.pageStage(8) }
                                    text: !root.analyticsTotals.requests ? root.analyticsStatus : root.analyticsStatus + " · " + root.countText(root.analyticsTotals.requests) + " requests · " + root.countText(root.analyticsTotals.cached) + " cached input tokens · " + root.countText(root.analyticsTotals.reasoning) + " reasoning tokens" + (root.analyticsTotals.costComplete ? "" : " · Cost estimate unavailable for one or more models.") }
                                Rectangle { opacity: root.pageStage(9); transform: ItemGrowth { stage: root.pageStage(9) }
                                    id: analyticsGraph
                                    Layout.fillWidth: true; implicitHeight: 260; radius: 22; color: root.cardColor
                                    Canvas {
                                        anchors.fill: parent
                                        property var points: root.analyticsPlot
                                        property string period: root.analyticsPeriod
                                        property string metric: root.analyticsMetric
                                        property string mode: prefs.chartMode
                                        property color gridColor: root.track
                                        property color labelColor: root.muted
                                        onPointsChanged: requestPaint()
                                        onPeriodChanged: requestPaint()
                                        onMetricChanged: requestPaint()
                                        onModeChanged: requestPaint()
                                        onGridColorChanged: requestPaint()
                                        onLabelColorChanged: requestPaint()
                                        onWidthChanged: requestPaint()
                                        onHeightChanged: requestPaint()
                                        onPaint: {
                                            let c = getContext("2d"); c.reset()
                                            let left = 54, right = 18, top = 18, bottom = 38
                                            let w = Math.max(1,width-left-right), h = Math.max(1,height-top-bottom)
                                            let max = 1
                                            points.forEach(series => series.points.forEach(point => { max = Math.max(max, Number(point.value) || 0) }))
                                            c.font = "11px sans-serif"; c.fillStyle = labelColor; c.strokeStyle = gridColor; c.lineWidth = 1
                                            for (let i=0;i<=4;i++) {
                                                let value = max*(1-i/4), y = top+h*i/4
                                                c.beginPath(); c.moveTo(left,y); c.lineTo(left+w,y); c.stroke()
                                                c.fillText(metric === "cost" ? "$"+value.toFixed(value<1?2:1) : root.countText(value), 4, y+4)
                                            }
                                            let end=Date.now()/1000, start=end-Number(period)*86400
                                            let interval=period==="1"?3600:86400
                                            let step=Math.max(interval,Math.ceil((end-start)/4/interval)*interval)
                                            c.fillStyle=labelColor; c.textAlign="center"
                                            for(let time=Math.ceil(start/step)*step;time<=end;time+=step){
                                                let x=left+w*(time-start)/(end-start), date=new Date(time*1000)
                                                let label=period==="1"?date.toLocaleTimeString(undefined,{hour:"numeric"}):date.toLocaleDateString(undefined,{month:"short",day:"numeric"})
                                                c.fillText(label,x,height-12)
                                            }
                                            c.textAlign="start"
                                            if (!points.length || !points.some(series => series.points.length)) return
                                            if (mode === "bars") {
                                                let count=points[0].points.length, groupWidth=w/Math.max(count,1)
                                                let bar=Math.max(1,Math.min(16,groupWidth/Math.max(points.length,1)*0.72))
                                                points.forEach((series,seriesIndex)=>{
                                                    c.fillStyle=root.providerColor(series.provider)
                                                    series.points.forEach(point=>{
                                                        let x=left+w*(point.time-start)/(end-start)+(seriesIndex-(points.length-1)/2)*bar
                                                        let bh=h*point.value/max
                                                        c.fillRect(x-bar/2,top+h-bh,bar,bh)
                                                    })
                                                })
                                            } else {
                                                c.lineWidth=2.4; c.lineJoin="round"; c.lineCap="round"
                                                points.forEach(series=>{
                                                    if(series.points.length<2)return
                                                    c.strokeStyle=root.providerColor(series.provider)
                                                    let coords=series.points.map(point=>({x:left+w*(point.time-start)/(end-start),y:top+h*(1-point.value/max)}))
                                                    c.beginPath(); c.moveTo(coords[0].x,coords[0].y)
                                                    for(let index=1;index<coords.length;index++){
                                                        let previous=coords[index-1],current=coords[index]
                                                        let midX=(previous.x+current.x)/2,midY=(previous.y+current.y)/2
                                                        c.quadraticCurveTo(previous.x,previous.y,midX,midY)
                                                    }
                                                    c.lineTo(coords[coords.length-1].x,coords[coords.length-1].y)
                                                    c.stroke()
                                                })
                                            }
                                        }
                                    }
                                    MText { anchors.centerIn: parent; visible: root.analyticsPlot.length === 0; text: root.analyticsMetric === "cost" && root.analyticsTotals.requests ? "A complete cost estimate is unavailable for this period" : "No token activity for this period"; color: root.muted; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; width: parent.width-48 }
                                }
                                SectionTitle { opacity: root.pageStage(10); transform: ItemGrowth { stage: root.pageStage(10) }
                                    text: "Accounts" }
                                Repeater {
                                    model: root.analyticsAccounts
                                    delegate: RowLayout {
                                        required property var modelData
                                        required property int index
                                        opacity: root.pageStage(index+11); transform: ItemGrowth { stage: root.pageStage(index+11) }
                                        Layout.fillWidth: true; spacing: 10
                                        Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: index % 2 === 0 ? root.primary : root.weeklyColor }
                                        MText { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.name || modelData.id }
                                        Rectangle { visible: modelData.authKind === "api_key"; radius: 10; color: root.track; implicitWidth: apiBadge.implicitWidth+14; implicitHeight: 22
                                            MText { id: apiBadge; anchors.centerIn: parent; text: "API"; color: root.foreground; font.pixelSize: 10; font.weight: Font.DemiBold }
                                        }
                                        MText { text: root.countText(modelData.input) + " in · " + root.countText(modelData.output) + " out · " + root.countText(modelData.requests) + " requests"; color: root.muted; font.pixelSize: 11 }
                                    }
                                }
                                Description { visible: root.analyticsTotals.requests === 0; opacity: root.pageStage(12); transform: ItemGrowth { stage: root.pageStage(12) }
                                    text: "Usage appears here after a Codex session records token counts. API-key accounts can show usage here while quota resources remain unavailable." }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Behaviour"; Layout.fillWidth: true; spacing: 14
                                RowLayout { opacity: root.pageStage(1); transform: ItemGrowth { stage: root.pageStage(1) }
                                    MText { text: "Hover activation"; Layout.fillWidth: true } MSwitch { checked: prefs.hoverEnabled; onToggled: prefs.hoverEnabled = checked } }
                                RowLayout { opacity: root.pageStage(2); transform: ItemGrowth { stage: root.pageStage(2) }
                                    MText { text: "Allow over full-screen apps"; Layout.fillWidth: true } MSwitch { checked: prefs.fullscreenOverride; onToggled: prefs.fullscreenOverride = checked } }
                                Description { opacity: root.pageStage(3); transform: ItemGrowth { stage: root.pageStage(3) }
                                    text: "Off by default. The hotspot stays hidden while a full-screen window is active." }
                                SectionTitle { opacity: root.pageStage(4); transform: ItemGrowth { stage: root.pageStage(4) }
                                    text: "Activation position" }
                                Rectangle { opacity: root.pageStage(3); transform: ItemGrowth { stage: root.pageStage(3) }
                                    
                                    Layout.fillWidth: true; implicitHeight: 144; radius: 20; color: root.cardColor
                                    GridLayout { anchors.fill: parent; anchors.margins: 12; columns: 3; rowSpacing: 6; columnSpacing: 6
                                        Repeater {
                                            model: ["top-left","top-center","top-right","left-center","","right-center","bottom-left","bottom-center","bottom-right"]
                                            delegate: HotspotChoice { required property string modelData; Layout.fillWidth: true; Layout.fillHeight: true; position: modelData }
                                        }
                                    }
                                }
                                Description { opacity: root.pageStage(4); transform: ItemGrowth { stage: root.pageStage(4) }
                                    text: prefs.hotspot.replace("-", " ") }
                                RowLayout { opacity: root.pageStage(5); transform: ItemGrowth { stage: root.pageStage(5) }
                                    MText { text: "Hotspot size · " + prefs.hotspotSize + " px"; Layout.fillWidth: true } MSlider { from: 32; to: 72; stepSize: 4; value: prefs.hotspotSize; onMoved: prefs.hotspotSize = Math.round(value) } }
                                RowLayout { opacity: root.pageStage(6); transform: ItemGrowth { stage: root.pageStage(6) }
                                    MText { text: "Dismiss delay · " + prefs.dismissDelay + " ms"; Layout.fillWidth: true } MSlider { from: 100; to: 1000; stepSize: 50; value: prefs.dismissDelay; onMoved: prefs.dismissDelay = Math.round(value) } }
                                RowLayout { opacity: root.pageStage(7); transform: ItemGrowth { stage: root.pageStage(7) }
                                    MText { text: "Cache refresh · " + prefs.cacheSeconds + " s"; Layout.fillWidth: true } MSlider { from: 2; to: 30; stepSize: 1; value: prefs.cacheSeconds; onMoved: prefs.cacheSeconds = Math.round(value) } }
                                Description { opacity: root.pageStage(8); transform: ItemGrowth { stage: root.pageStage(8) }
                                    text: "The daemon collects quotas every three minutes. This setting only changes how often the drawer reads its cache." }
                                Choice { opacity: root.pageStage(9); transform: ItemGrowth { stage: root.pageStage(9) }
                                    label: "Restore defaults"; onChosen: { prefs.followTheme=true; prefs.colorScheme="mono"; prefs.hoverEnabled=true; prefs.fullscreenOverride=false; prefs.motionMs=240; prefs.dataMotionMs=450; prefs.dismissDelay=350; prefs.layoutWidth=440; prefs.cacheSeconds=5; prefs.viewMode="grid"; prefs.hotspot="top-right"; prefs.staggerEnabled=true; prefs.hiddenProviders="[]"; prefs.hiddenAccounts="[]"; prefs.chartMode="line"; prefs.hotspotSize=40; prefs.hotspotRevision=1; prefs.fontChoice="auto"; prefs.cardRadius=24; prefs.edgeFades=true; prefs.fadeDepth=28; prefs.localShortcutsEnabled=true; prefs.globalShortcutsEnabled=true; prefs.shortcutBindings="{}"; prefs.bindSyntax="conf"; prefs.motionStyle="liquid"; prefs.trackpadSpeed=1.6; prefs.wispMotion=true } }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Shortcuts"; Layout.fillWidth: true; spacing: 14
                                SectionTitle { opacity: root.pageStage(1); transform: ItemGrowth { stage: root.pageStage(1) }
                                    text: "Desktop shortcuts" }
                                Description { opacity: root.pageStage(2); transform: ItemGrowth { stage: root.pageStage(2) }
                                    text: "Open aether from anywhere in Hyprland. Choose a modifier and key, then copy the generated configuration into your own keybind file. Existing desktop bindings are never changed automatically." }
                                RowLayout { opacity: root.pageStage(3); transform: ItemGrowth { stage: root.pageStage(3) }
                                    
                                    Layout.fillWidth: true
                                    MText { text: "Generate desktop bindings"; Layout.fillWidth: true }
                                    MSwitch { checked: prefs.globalShortcutsEnabled; onToggled: prefs.globalShortcutsEnabled = checked }
                                }
                                Repeater {
                                    model: root.shortcutActions
                                    delegate: Rectangle {
                                        id: actionCard
                                        required property int index
                                        required property var modelData
                                        property var binding: root.bindingFor(modelData)
                                        Layout.fillWidth: true; implicitHeight: bindingContent.implicitHeight + 24
                                        radius: 18; color: root.cardColor
                                        border.width: 1; border.color: root.outline
                                        opacity: (prefs.globalShortcutsEnabled ? 1 : 0.55) * root.pageStage(index+4); transform: ItemGrowth { stage: root.pageStage(index+4) }
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
                                                    onActivated: function(index) { root.setBinding(actionCard.modelData, "mods", model[index]) }
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
                                                    onActivated: function(index) { root.setBinding(actionCard.modelData, "key", model[index]) }
                                                }
                                            }
                                        }
                                    }
                                }
                                Description { opacity: root.pageStage(7); transform: ItemGrowth { stage: root.pageStage(7) }
                                    visible: prefs.globalShortcutsEnabled && root.duplicateBindings; color: root.danger; text: "Two aether actions use the same shortcut. Choose different combinations before copying." }
                                RowLayout { opacity: root.pageStage(8); transform: ItemGrowth { stage: root.pageStage(8) }
                                    
                                    Layout.fillWidth: true
                                    MText { text: "Hyprland configuration"; Layout.fillWidth: true; font.weight: Font.Medium }
                                    LiquidSelect { Layout.preferredWidth: 160; model: ["Legacy .conf","Lua"]; currentIndex: prefs.bindSyntax === "lua" ? 1 : 0; onActivated: function(index) { prefs.bindSyntax = index === 1 ? "lua" : "conf" }}
                                }
                                TextArea { opacity: root.pageStage(9); transform: ItemGrowth { stage: root.pageStage(9) }
                                    
                                    id: bindingText
                                    Layout.fillWidth: true; Layout.preferredHeight: Math.max(120, Math.min(240, contentHeight + 24))
                                    readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere
                                    focusPolicy: Qt.NoFocus; activeFocusOnPress: false
                                    text: root.hyprlandBindings
                                    color: root.foreground; selectionColor: root.primary; selectedTextColor: root.onAccent
                                    font.family: root.monoFont; font.pixelSize: 11; padding: 12
                                    background: Rectangle { radius: 16; color: root.cardColor; border.width: 1; border.color: root.outline }
                                }
                                RowLayout { opacity: root.pageStage(10); transform: ItemGrowth { stage: root.pageStage(10) }
                                    
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
                                Description { opacity: root.pageStage(11); transform: ItemGrowth { stage: root.pageStage(11) }
                                    text: "Replace any previously installed aether binds in your Hyprland configuration, check for conflicts with existing desktop shortcuts, then reload Hyprland. Changing or disabling a binding here only updates the generated text; remove the previous compositor binding yourself." }
                                SectionTitle { opacity: root.pageStage(12); transform: ItemGrowth { stage: root.pageStage(12) }
                                    text: "Inside the control centre" }
                                RowLayout { opacity: root.pageStage(13); transform: ItemGrowth { stage: root.pageStage(13) }
                                    
                                    Layout.fillWidth: true
                                    MText { text: "Enable in-app shortcuts"; Layout.fillWidth: true }
                                    MSwitch { checked: prefs.localShortcutsEnabled; onToggled: prefs.localShortcutsEnabled = checked }
                                }
                                Repeater {
                                    model: root.settingsPages.concat(["Refresh local view","Close control centre"])
                                    delegate: Rectangle {
                                        id: localRow
                                        opacity: root.pageStage(index+10); transform: ItemGrowth { stage: root.pageStage(index+10) }
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
                                Description { opacity: root.pageStage(17); transform: ItemGrowth { stage: root.pageStage(17) }
                                    text: "In-app shortcuts work when the control centre has keyboard focus. The hover drawer deliberately does not steal focus." }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "Updates"; Layout.fillWidth: true; spacing: 16
                                Description { opacity: root.pageStage(1); transform: ItemGrowth { stage: root.pageStage(1) }
                                    text: "Keep aether up to date from its official GitHub repository. Automatic installation is opt-in. Updates do not modify your project checkout, credentials or preferences." }
                                Rectangle { opacity: root.pageStage(2); transform: ItemGrowth { stage: root.pageStage(2) }
                                    
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
                                RowLayout { opacity: root.pageStage(3); transform: ItemGrowth { stage: root.pageStage(3) }
                                    
                                    Layout.fillWidth: true
                                    MText { text: "Automatically install updates"; Layout.fillWidth: true }
                                    MSwitch { checked: prefs.autoUpdate; onToggled: { prefs.autoUpdate = checked; prefs.sync() } }
                                }
                                SectionTitle { opacity: root.pageStage(4); transform: ItemGrowth { stage: root.pageStage(4) }
                                    text: "Update channel" }
                                RowLayout { opacity: root.pageStage(5); transform: ItemGrowth { stage: root.pageStage(5) }
                                    
                                    Layout.fillWidth: true
                                    LiquidSelect { Layout.fillWidth: true; model: ["Stable releases","Development"]; currentIndex: prefs.updateChannel === "development" ? 1 : 0; onActivated: function(index) { prefs.updateChannel = index === 1 ? "development" : "stable"; prefs.sync(); root.runUpdater("status") } }
                                }
                                Description { opacity: root.pageStage(6); transform: ItemGrowth { stage: root.pageStage(6) }
                                    text: prefs.updateChannel === "stable" ? "Only published, non-prerelease GitHub releases. Until a release is published, there is no stable update." : "Tracks main commits. Development builds may introduce regressions; choose Stable if you prefer fewer changes." }
                                RowLayout { opacity: root.pageStage(7); transform: ItemGrowth { stage: root.pageStage(7) }
                                    
                                    Layout.fillWidth: true
                                    Choice { label: "Check for updates"; enabled: !updateReader.running && !root.updateInfo.busy; onChosen: root.runUpdater("check") }
                                    Choice { label: "Install update"; enabled: !updateReader.running && !root.updateInfo.busy; onChosen: root.runUpdater("apply") }
                                    Choice { label: "Roll back"; enabled: !updateReader.running && !root.updateInfo.busy && !!root.updateInfo.rollbackAvailable; onChosen: root.runUpdater("rollback") }
                                }
                                Description { opacity: root.pageStage(8); transform: ItemGrowth { stage: root.pageStage(8) }
                                    text: "The systemd user timer checks every six hours when automatic installation is enabled. The updater builds before replacing files, refuses downgrades or divergent commits, and restores previous files on installation errors. A previous build is retained for manual rollback. No sudo. If Quickshell does not reload automatically, restart only aether." }
                                LinkRow { opacity: root.pageStage(9); transform: ItemGrowth { stage: root.pageStage(9) }
                                    label: "Release history ↗"; url: "https://github.com/maynkudu/aether-ai/releases" }
                                LinkRow { opacity: root.pageStage(10); transform: ItemGrowth { stage: root.pageStage(10) }
                                    label: "Development commits ↗"; url: "https://github.com/maynkudu/aether-ai/commits/main" }
                            }
                            ColumnLayout {
                                visible: root.settingsTab === "About"; Layout.fillWidth: true; spacing: 16
                                Rectangle { opacity: root.pageStage(1); transform: ItemGrowth { stage: root.pageStage(1) }
                                    
                                    Layout.fillWidth: true; implicitHeight: 222; radius: 26; color: root.cardColor
                                    ColumnLayout { anchors.fill: parent; anchors.margins: 24; spacing: 8
                                        RowLayout { Layout.fillWidth: true
                                            Description { text: "INDEPENDENT SOFTWARE"; font.pixelSize: 11; font.letterSpacing: 1.3 }
                                            Choice { label: "MIT"; onChosen: Qt.openUrlExternally("https://github.com/maynkudu/aether-ai/blob/main/LICENSE") }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 12
                                            WispMark { Layout.preferredWidth: 46; Layout.preferredHeight: 46 }
                                            MText { text: "aether.ai"; font.pixelSize: 48; font.weight: Font.DemiBold; font.letterSpacing: -2.2; Layout.fillWidth: true; elide: Text.ElideRight }
                                        }
                                        Description { text: "Intelligence, within limits." }
                                        Description { text: "Meet Wisp, our little quota companion."; font.pixelSize: 12 }
                                        Item { Layout.fillHeight: true }
                                        RowLayout { Layout.fillWidth: true
                                            MText { text: "v" + root.version; font.family: root.monoFont; color: root.primary }
                                            Item { Layout.fillWidth: true }
                                            Description { text: "Rust × Quickshell"; Layout.fillWidth: false }
                                        }
                                    }
                                }
                                SectionTitle { opacity: root.pageStage(2); transform: ItemGrowth { stage: root.pageStage(2) }
                                    text: "Made by" }
                                LinkRow { opacity: root.pageStage(3); transform: ItemGrowth { stage: root.pageStage(3) }
                                    label: "maynkudu · Creator"; url: "https://github.com/maynkudu" }
                                LinkRow { opacity: root.pageStage(4); transform: ItemGrowth { stage: root.pageStage(4) }
                                    label: "Project contributors"; url: "https://github.com/maynkudu/aether-ai/graphs/contributors" }
                                SectionTitle { opacity: root.pageStage(5); transform: ItemGrowth { stage: root.pageStage(5) }
                                    text: "Open-source community" }
                                LinkRow { opacity: root.pageStage(6); transform: ItemGrowth { stage: root.pageStage(6) }
                                    label: "GitHub repository"; githubIcon: true; url: "https://github.com/maynkudu/aether-ai" }
                                LinkRow { opacity: root.pageStage(7); transform: ItemGrowth { stage: root.pageStage(7) }
                                    label: "Issues & feature requests"; url: "https://github.com/maynkudu/aether-ai/issues" }
                                LinkRow { opacity: root.pageStage(8); transform: ItemGrowth { stage: root.pageStage(8) }
                                    label: "Changelog"; url: "https://github.com/maynkudu/aether-ai/blob/main/CHANGELOG.md" }
                                LinkRow { opacity: root.pageStage(9); transform: ItemGrowth { stage: root.pageStage(9) }
                                    label: "MIT license"; url: "https://github.com/maynkudu/aether-ai/blob/main/LICENSE" }
                                LinkRow { opacity: root.pageStage(10); transform: ItemGrowth { stage: root.pageStage(10) }
                                    label: "Brand artwork sources"; url: "https://github.com/maynkudu/aether-ai/blob/main/shell/BRAND-ASSETS.md" }
                                Description { opacity: root.pageStage(11); transform: ItemGrowth { stage: root.pageStage(11) }
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
