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
    property var clientUsage: []
    property bool usageReady: false
    property bool cacheReady: false
    property string analyticsError: ""
    property bool analyticsLoading: analyticsReader.running
    property bool cacheLoading: reader.running
    property bool localDataLoading: analyticsLoading || cacheLoading
    property string loadingMessage: cacheLoading && !cacheReady ? "Reading cached limits…" : analyticsLoading ? "Reading local usage…" : cacheLoading ? "Refreshing cached limits…" : analyticsError || (analyticsUpdatedAt ? "Local usage updated " + Qt.formatTime(new Date(analyticsUpdatedAt),"HH:mm") : "Waiting for local usage")
    property double analyticsUpdatedAt: 0
    function usageSum(rows) {
        let total={inputTokens:0,outputTokens:0,cachedInputTokens:0,totalTokens:0,steps:0,costUsd:null,costComplete:true,tokensComplete:true}
        for(let row of rows) {
            for(let key of ["inputTokens","outputTokens","cachedInputTokens","totalTokens","steps"]) total[key]+=Number(row[key] || 0)
            if(typeof row.costUsd === "number") total.costUsd=Number(total.costUsd || 0)+row.costUsd
            else total.costComplete=false
            if(row.costComplete === false) total.costComplete=false
            if(row.tokensComplete === false) total.tokensComplete=false
        }
        return total
    }
    function codexUsage(rows) {
        return usageSum(rows.map(r => ({inputTokens:r.inputTokens,outputTokens:r.outputTokens,cachedInputTokens:r.cachedInputTokens,totalTokens:r.totalTokens,steps:r.requestCount,costUsd:r.estimatedCostUsd})))
    }
    function accountUsage(account) {
        let client=root.logo(account.provider)
        if(client === "codex") {
            let rows=root.analyticsRows.filter(r => r.id === account.id)
            return rows.length ? {available:true,totals:codexUsage(rows),scope:"This account",sourceKey:"codex:"+account.id,estimated:true} : {available:false}
        }
        if(client === "opencode") {
            if(root.openCodeAnalytics.status !== "ok") {
                if(account.authKind === "free" && account.activity) return {available:true,totals:account.activity,scope:"Enabled free models · cached 7 days",sourceKey:"opencode:free",periodDays:7,partial:true}
                return {available:false}
            }
            let models=root.openCodeModels
            let scope="All OpenCode usage on this device"
            let source=account.usageProvider || "device"
            if(account.authKind === "free") {
                let ids=(account.freeModels || []).map(m => m.providerID+"/"+(m.modelID || m.id))
                models=models.filter(m => ids.includes(m.providerID+"/"+m.modelID));scope="Enabled free models"
            } else if(account.usageProvider) {
                models=models.filter(m => m.providerID === account.usageProvider);scope=account.usageProvider+" through OpenCode"
                if(!models.length) { models=root.openCodeModels;scope="All OpenCode usage on this device";source="device" }
            }
            if(!models.length) return {available:false}
            let totals=usageSum(models)
            return {available:true,totals:totals,scope:scope,sourceKey:account.authKind === "free" ? "opencode:free" : "opencode:"+source,shared:source === "device" && account.authKind !== "free",estimated:true}
        }
        let data=root.clientUsage.find(c => c.provider === account.provider)
        if(!data || data.status !== "ok") return {available:false}
        let home=(data.accounts || []).find(p => p.id === account.id)
        if(home) return home.status === "empty" ? {available:false} : {available:true,totals:home.totals,scope:"This client profile",sourceKey:client+":"+account.id,estimated:data.estimated,partial:data.partial}
        let exact=(data.providers || []).find(p => p.providerID === account.usageProvider)
        return {available:true,totals:exact ? exact.totals : data.totals,scope:exact ? account.usageProvider+" through "+account.provider : "All "+account.provider+" usage on this device",sourceKey:client+":"+(exact ? account.usageProvider : "device"),shared:!exact,estimated:data.estimated,partial:data.partial}
    }
    property var overviewClients: {
        let result=[]
        let visibleClients=Array.from(new Set(root.accounts.map(a => a.provider)))
        let codex=root.analyticsRows
        if(codex.length && visibleClients.includes("Codex")) result.push({provider:"Codex",totals:codexUsage(codex)})
        if(visibleClients.includes("OpenCode") && !root.hiddenProviders.includes("opencode") && root.openCodeAnalytics.status === "ok") result.push({provider:"OpenCode",totals:root.openCodeAnalytics.totals})
        for(let client of root.clientUsage) if(visibleClients.includes(client.provider) && client.status === "ok" && !root.hiddenProviders.includes(root.logo(client.provider))) result.push(client)
        return result
    }
    property int visibleClientCount: new Set(root.accounts.map(a => a.provider)).size
    property string overviewHeading: root.accounts.length+" account"+(root.accounts.length===1?"":"s")+". "+visibleClientCount+" client"+(visibleClientCount===1?"":"s")+"."
    property var overviewTotals: usageSum(overviewClients.map(c => c.totals))
    property int quotaAccountCount: accounts.filter(a => (a.windows || []).length > 0).length
    property int attentionAccountCount: accounts.filter(a => ["login_required","forbidden","rate_limited"].includes(a.status)).length
    property string usagePeriodText: analyticsPeriod === "1" ? "Last 24 hours" : "Last "+analyticsPeriod+" days"
    function usageCost(totals) { return totals.costUsd === 0 ? "—" : root.costText(totals.costUsd) }
    function accountHasData(account) { return (account.windows || []).length>0 || (account.authKind === "free" && (account.freeModels || []).length>0) || root.hasUsageData(root.accountUsage(account)) }
    function hasUsageData(usage) { return !!usage.available }
    function authTier(account) {
        if(["oauth","chatgpt"].includes(account.authKind)) return 0
        if(account.authKind === "api_key") return 1
        return 2
    }
    function authLabel(account) {
        return root.authTier(account) === 0 ? "OAuth" : account.authKind === "api_key" ? "API key" : account.authKind === "free" ? "Free models" : account.authKind === "console" ? "Console" : ""
    }
    function accountRows(accounts) {
        let oauth=accounts.filter(r => root.authTier(r.account)===0)
        let api=accounts.filter(r => root.authTier(r.account)===1)
        let other=accounts.filter(r => root.authTier(r.account)===2)
        let rows=[]
        if(oauth.length===1 && api.length+other.length===1) return [[oauth[0],...api,...other]]
        for(let i=0;i<oauth.length;i+=2) rows.push(oauth.slice(i,i+2))
        // Keep a lone API account beside its free-model or unknown-account peer.
        if(api.length===1 && other.length===1) rows.push([api[0],other[0]])
        else for(let list of [api,other]) for(let i=0;i<list.length;i+=2) rows.push(list.slice(i,i+2))
        return rows
    }
    function overviewGroups() {
        let groups=[]
        for(let account of root.accounts) {
            let usage=root.accountUsage(account)
            let hasLimits=(account.windows || []).length>0
            let hasData=hasLimits || root.hasUsageData(usage)
            let group=groups.find(g => g.provider===account.provider)
            if(!group) { group={provider:account.provider,accounts:[],sharedUsage:[],sharedKeys:[],hasData:false};groups.push(group) }
            group.hasData=group.hasData || hasData
            group.accounts.push({account:account,usage:usage,hasLimits:hasLimits,hasData:hasData})
        }
        for(let group of groups) {
            let keys=[]
            for(let row of group.accounts) if(row.usage.available && !keys.includes(row.usage.sourceKey)) keys.push(row.usage.sourceKey)
            for(let key of keys) {
                let matches=group.accounts.filter(r => r.usage.sourceKey===key && root.hasUsageData(r.usage))
                if(matches.length>1) { group.sharedKeys.push(key);group.sharedUsage.push(matches[0].usage) }
            }
            group.accounts.sort((a,b) => root.authTier(a.account)-root.authTier(b.account) || Number(b.hasData)-Number(a.hasData) || String(a.account.name).localeCompare(String(b.account.name)))
            group.rows=root.accountRows(group.accounts)
        }
        let order=["Codex","OpenCode","Pi","Claude Code"]
        return groups.sort((a,b) => Number(b.hasData)-Number(a.hasData) || order.indexOf(a.provider)-order.indexOf(b.provider))
    }
    property var overviewAccountGroups: overviewGroups()
    function accountSummary(account) {
        if(account.authKind === "free") return root.compactValue(account)+" free models"
        if((account.windows || []).length) return account.status === "stale" ? "Last known limits" : "Limits available"
        if(account.status === "login_required") return "Sign-in needed for limits"
        return "Limits not reported"
    }

    property var accounts: allAccounts.filter(a => !removedProvider(a.provider) && !hiddenProviders.includes(logo(a.provider)) && !hiddenAccounts.includes(String(a.id)) && (!prefs.hideUnavailableAccounts || !root.usageReady || root.accountHasData(a)))
    function compactAccount(account) {
        return account.authKind === "free" || (!root.windowFor(account,300) && !root.windowFor(account,10080))
    }
    property var quotaAccounts: accounts.filter(a => !compactAccount(a))
    property var compactAccounts: accounts.filter(a => compactAccount(a))
    function extraWindows(account) { return (account.windows || []).filter(w => Number(w.minutes) !== 300 && Number(w.minutes) !== 10080) }
    function windowLabel(window) { return window.label || (window.minutes === 10080 ? "Weekly" : window.minutes === 300 ? "5-hour session" : window.minutes ? (window.minutes/60) + "h window" : "Quota") }
    function windowValue(window) { return window.remainingUsd !== undefined ? "$" + Number(window.remainingUsd).toFixed(2) + " left" : root.remaining(window) < 0 ? "—" : Math.round(root.remaining(window)) + "%" }
    function compactTitle(account) { return account.authKind === "free" ? "" : (account.windows || []).length ? "Budget" : root.authLabel(account) }
    function compactValue(account) {
        if (account.status === "stale") return "Last known data"
        if (account.authKind === "free") return (account.freeModels || []).length + " enabled"
        if ((account.windows || []).length) return account.windows.length + " limit" + (account.windows.length === 1 ? "" : "s")
        if (account.status === "no_allowance") return "No Go allowance"
        return !root.usageReady ? "Reading usage" : root.hasUsageData(root.accountUsage(account)) ? "Local usage" : "No local data"
    }
    function compactHint(account) {
        if (account.authKind === "free") return (account.freeModels || []).slice(0,12).map(m => m.name).join("\n") + ((account.freeModels || []).length > 12 ? "\nMore models in OpenCode" : "") + "\nRemaining free limits aren't reported."
        return root.accountStatus(account)
    }
    function freeLimitModels(account) {
        return (account.freeModels || []).filter(m => m.observation && m.observation.limitObservedAt && !(m.observation.lastSuccessAt > m.observation.limitObservedAt))
            .sort((a,b) => Number(b.observation.retryAt > root.now)-Number(a.observation.retryAt > root.now) || b.observation.limitObservedAt-a.observation.limitObservedAt)
    }
    function freeLimitText(model) {
        let o = model.observation || {}
        if (o.lastSuccessAt > o.limitObservedAt) return "Used after last limit"
        if (o.retryAt > root.now) return root.resetText(o.retryAt/1000).replace("Resets in", "Retry in")
        if (o.retryAt) return "Retry time passed"
        return "Limit observed; retry time unknown"
    }
    function freeActivityText(account) {
        let activity = account.activity
        if (!activity) return "Local usage unavailable"
        return activity.days + " days · " + root.countText(activity.steps) + " steps · " + root.countText(activity.totalTokens) + " tokens" + (account.activityStatus === "stale" ? " · cached" : account.activityStatus === "partial" ? " · partial" : "")
    }
    function openCodeModelName(model) {
        let free = allAccounts.find(a => a.authKind === "free")
        let entry = free && (free.freeModels || []).find(m => m.modelID === model.modelID && m.providerID === model.providerID)
        return entry ? entry.name : model.modelID
    }
    function openCodeObservation(model) {
        let free = allAccounts.find(a => a.authKind === "free")
        return free && (free.freeModels || []).find(m => m.modelID === model.modelID && m.providerID === model.providerID) || ({})
    }
    function removedProvider(provider) {
        let id = String(provider || "").toLowerCase().replace(/[^a-z0-9]/g, "")
        return id.startsWith("agentrouter") || id.startsWith("freegg")
    }
    // Rows are keyed by account IDs so cache refreshes keep gauges alive.
    property var drawerRows: []
    property var drawerAccountIds: {
        let ids=[]
        for(let row of drawerRows) ids=ids.concat(row)
        return ids
    }
    function syncDrawerRows() {
        let rows=[]
        for(let group of overviewAccountGroups) for(let row of group.rows) rows.push(row.map(item => String(item.account.id)))
        if(JSON.stringify(rows)!==JSON.stringify(drawerRows)) drawerRows=rows
    }
    onOverviewAccountGroupsChanged: Qt.callLater(syncDrawerRows)
    property var hiddenProviders: parseList(prefs.hiddenProviders)
    property var hiddenAccounts: parseList(prefs.hiddenAccounts)
    function parseList(value) { try { let a = JSON.parse(value); return Array.isArray(a) ? a : [] } catch(e) { return [] } }
    function setHidden(key, value, hidden) {
        let list = parseList(prefs[key]).filter(x => x !== value)
        if (hidden) list.push(value)
        prefs[key] = JSON.stringify(list)
    }
    property var providerCatalog: {
        let result = [{id:"codex",name:"Codex"},{id:"claude",name:"Claude Code"},{id:"opencode",name:"OpenCode"},{id:"pi",name:"Pi"}]
        for (let a of allAccounts) {
            if (removedProvider(a.provider)) continue
            let id = logo(a.provider)
            if (id && !result.some(p => p.id === id)) result.push({id:id,name:a.provider})
        }
        return result
    }
    property var providerGroups: {
        let groups = [
            {name:"First-party agents",note:"Provider-operated coding agents",ids:["codex","claude"]},
            {name:"Coding clients",note:"Quotas belong to each connected provider account",ids:["opencode","pi"]},
            {name:"Other providers",note:"Additional model providers and integrations",ids:[]}
        ]
        let assigned = groups[0].ids.concat(groups[1].ids), rows = []
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
        refreshAnalytics()
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
    property var openCodeAnalytics: ({status:"not_detected"})
    property var openCodeModels: (openCodeAnalytics.models || []).slice().sort((a,b) => b.totalTokens-a.totalTokens)
    property string analyticsStatus: "No local token usage found"
    Process {
        id: analyticsReader
        property string requestedPeriod: "7"
        command: [Quickshell.env("HOME") + "/.local/bin/aether", "analytics", requestedPeriod]
        onExited: (code, status) => {
            if (requestedPeriod !== root.analyticsPeriod) Qt.callLater(root.refreshAnalytics)
            else if (code !== 0) { root.usageReady = true; root.analyticsError = "Could not update local usage. Refresh to retry." }
        }
        stdout: StdioCollector { onStreamFinished: {
            if (analyticsReader.requestedPeriod !== root.analyticsPeriod) return
            try {
                let data = JSON.parse(text)
                root.analyticsSamples = data.samples || []
                root.openCodeAnalytics = data.openCode || ({status:"not_detected"}); root.clientUsage=data.clients || []
                root.usageReady = true; root.analyticsError = ""; root.analyticsUpdatedAt = Date.now()
                root.analyticsStatus = root.analyticsSamples.length ? "Local Codex session logs" : "No local token usage found for this period"
            } catch(e) { root.usageReady = true; root.analyticsError = "Could not read local usage. Refresh to retry."; root.analyticsStatus = root.analyticsError }
        } }
    }
    function refreshAnalytics() { if (!analyticsReader.running) { analyticsError = ""; analyticsReader.requestedPeriod = analyticsPeriod; analyticsReader.running = true } }
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
        if (Number(value) === 0) return "—"
        if (Number(value) < 0.01) return "<$0.01"
        return "$" + Number(value).toFixed(2)
    }
    onAnalyticsPeriodChanged: { analyticsSamples = []; clientUsage = []; usageReady = false; openCodeAnalytics = ({status:"loading"}); refreshAnalytics(); if (settingsOpen && settingsTab === "Analytics") pageDataClock.jump(0) }
    onAnalyticsMetricChanged: if (settingsOpen && settingsTab === "Analytics") pageDataClock.jump(0)
    onSettingsOpenChanged: if (settingsOpen) { pageSpring.jump(0); pageDataClock.jump(0); if (!reader.running) reader.running = true; refreshAnalytics(); if (settingsTab === "Updates") runUpdater("status") } else if (activeDropdown) activeDropdown.close()
    Timer { interval: 30000; repeat: true; running: root.settingsOpen || root.opened; onTriggered: { root.now = Date.now(); root.refreshAnalytics() } }
    HyprlandFocusGrab {
        id: menuGrab
        windows: [settingsPanel,drawer]
        active: root.hyprlandAvailable && (root.settingsOpen || root.opened)
        onCleared: if (root.settingsOpen || root.opened) root.dismissAll()
    }
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
        if (prefs.motionStyle === "liquid") prefs.motionStyle = "smooth"
        if (prefs.hotspotRevision < 1) {
            if (prefs.hotspotSize < 32) prefs.hotspotSize = 40
            prefs.hotspotRevision = 1
        }
        syncDrawerRows()
        Qt.callLater(root.refreshAnalytics)
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
        let variant = root.lightTheme ? "light" : "dark"
        if (name === "openai") name = "codex"
        if (["codex","claude","opencode","pi"].includes(name)) return Qt.resolvedUrl("provider-logos/" + name + "-" + variant + ".png")
        let entry = root.brandIndex[name]
        let filename = entry && entry[variant]
        if (filename !== name + "-" + variant + ".png" || !/^[a-z0-9]{1,64}-(dark|light)\.png$/.test(filename)) return ""
        return Qt.resolvedUrl("brand-icons/" + filename)
    }
    onOpenedChanged: if (opened && Date.now()-analyticsUpdatedAt > 30000) root.refreshAnalytics()
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
    property real naturalHeight: Math.max(148, Math.min(drawer.height - 12, content.implicitHeight + 32))
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
        property bool animateInitial: false
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
        // Let direction-dependent bindings settle before selecting the timing.
        onTargetValueChanged: Qt.callLater(retarget)
        onInstantChanged: retarget()
        Component.onCompleted: {
            value = animateInitial && !instant ? 0 : targetValue
            ready = true
            if (animateInitial) retarget()
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
    // One reversible timeline keeps the panel, cards and their details in order.
    // Geometry settles first; each content stage gets the same easing window.
    MotionValue { id: drawerSpring; targetValue: root.opened ? 1 : 0; proportional: true; factor: 2.2; curve: Easing.Linear }
    property real reveal: quintic(drawerSpring.value / 0.62)
    function surfaceBounce(progress, width, height) {
        if (prefs.motionStyle === "reduced") return 0
        let phase = unit((progress - 0.35) / 0.65)
        let amplitude = Math.min(0.012, 4 / Math.max(1, width, height))
        return amplitude * Math.sin(2 * Math.PI * phase) * Math.pow(Math.sin(Math.PI * phase), 2)
    }
    function drawerBounce(progress) { return surfaceBounce(progress,panelWidth,panelHeight) }
    MotionValue { id: settingsSpring; targetValue: root.settingsOpen ? 1 : 0; proportional: true; factor: 2.2; curve: Easing.Linear }
    property real settingsReveal: quintic(settingsSpring.value / 0.62)
    property real settingsContentReveal: quintic((settingsSpring.value - 0.44) / 0.30)
    MotionValue { id: pageSpring; targetValue: root.settingsOpen && root.settingsContentReveal > 0.01 ? 1 : 0; factor: 1.05; proportional: true; curve: Easing.Linear }
    MotionValue { id: pageDataClock; targetValue: root.settingsOpen ? 1 : 0; factor: 1.40; dataMotion: true; proportional: true; curve: Easing.Linear }
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
    // Anchor coordinates in the stable overlay: 0 = near edge, 0.5 = centre, 1 = far edge.
    property real ax: prefs.hotspot.indexOf("left") >= 0 ? 0 : prefs.hotspot.indexOf("right") >= 0 ? 1 : 0.5
    property real ay: prefs.hotspot.indexOf("top") >= 0 ? 0 : prefs.hotspot.indexOf("bottom") >= 0 ? 1 : 0.5
    property real panelWidth: Math.max(1, drawer.width - 12)
    property real panelHeight: Math.min(drawer.height - 12, animatedHeight)
    property bool rings: prefs.viewMode === "rings"
    property color sessionColor: tone("primary", lightTheme ? "#222222" : "#e8e8e8")
    property color weeklyColor: tone("tertiary", lightTheme ? "#606060" : "#9b9b9b")
    property var drawerStages: {
        let next = 2
        let ordered = drawerAccountIds.map(id => accounts.find(a => String(a.id)===id)).filter(Boolean)
        let starts = ordered.map(account => {
            let start = next
            let compact = compactAccount(account)
            let status = account.status !== "ok" ? 1 : 0
            next += compact ? 3 + (account.windows || []).length : 2 + status + (rings ? 2 + root.extraWindows(account).length : (account.windows || []).length)
            return start
        })
        let footer = Math.max(3,next)
        return {accounts:starts,footer:footer,count:footer+1}
    }
    function stagger(i) {
        if (prefs.motionStyle === "reduced") return root.opened ? 1 : 0
        let spacing = prefs.staggerEnabled ? Math.min(0.055,0.26/Math.max(1,drawerStages.count-1)) : 0
        let start = 0.44 + Math.max(0,i)*spacing
        return quintic((drawerSpring.value-start)/0.30)
    }
    function windowFor(account, minutes) {
        let windows = account.windows || []
        return windows.find(w => Number(w.minutes) === minutes) || null
    }
    function remaining(w) {
        return w && w.remaining !== null && w.remaining !== undefined && isFinite(Number(w.remaining)) ? Math.max(0, Math.min(100, Number(w.remaining))) : -1
    }
    property bool settingsOpen: false
    Settings { id: prefs; location: "file:" + (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/aether/preferences.ini"; category: "AetherUI"; property bool followTheme: true; property bool hoverEnabled: true; property bool fullscreenOverride: false; property int motionMs: 240; property int dataMotionMs: 450; property int dismissDelay: 350; property int drawerWidth: 390; property int layoutWidth: 360; property int cacheSeconds: 5; property string viewMode: "grid"; property string hotspot: "top-right"; property bool staggerEnabled: true; property string hiddenProviders: "[]"; property string hiddenAccounts: "[]"; property string chartMode: "line"; property int hotspotSize: 40; property int hotspotRevision: 0; property string fontChoice: "auto"; property int cardRadius: 24; property string colorScheme: "mono"; property bool edgeFades: true; property int fadeDepth: 28; property bool localShortcutsEnabled: true; property bool globalShortcutsEnabled: true; property string shortcutBindings: "{}"; property string bindSyntax: "conf"; property string motionStyle: "smooth"; property bool autoUpdate: false; property string updateChannel: "stable"; property int motionRevision: 0; property real trackpadSpeed: 1.6; property bool wispMotion: true; property bool hideUnavailableAccounts: false }
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
        return /^[a-z0-9]{1,64}$/.test(s) ? s : ""
    }
    function accountStatus(account) {
        switch (account.status) {
        case "ok": return "Available"
        case "api_key": return "This API key doesn't expose usage limits."
        case "login_required": return "Sign in again in " + account.provider
        case "unsupported": return "Quota usage is unavailable for this sign-in"
        case "rate_limited": return "Provider rate limit reached. Waiting to retry."
        case "forbidden": return "Provider access restricted"
        case "no_allowance": return "No Go allowance or Console budget reported"
        case "free_available": return "Free models enabled. Remaining free limits aren't reported."
        case "free_unavailable": return "No free models enabled in OpenCode"
        case "unavailable": return "Quota usage unavailable"
        case "stale": return "Offline · last known quota"
        default: return String(account.status || "")
        }
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
    }
    component LoadingIndicator: Item {
        id: loadingIndicator
        property bool active: false
        property bool animating: active && visible && (root.opened || root.settingsOpen) && prefs.motionStyle !== "reduced"
        implicitWidth: 14; implicitHeight: 14
        visible: active
        Accessible.ignored: true
        Shape {
            anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
            rotation: 0
            NumberAnimation on rotation { running: loadingIndicator.animating; from: 0; to: 360; duration: Math.max(650,root.motionDuration(3)); loops: Animation.Infinite }
            ShapePath { fillColor: "transparent"; strokeColor: root.primary; strokeWidth: 2; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: loadingIndicator.width/2; centerY: loadingIndicator.height/2; radiusX: Math.max(1,loadingIndicator.width/2-2); radiusY: Math.max(1,loadingIndicator.height/2-2); startAngle: -90; sweepAngle: 270 }
            }
        }
    }
    component LoadingStatus: RowLayout {
        property bool active: false
        property string text: ""
        Accessible.role: Accessible.StaticText
        Accessible.name: text
        spacing: 7
        LoadingIndicator { active: parent.active; visible: active; Layout.preferredWidth: 13; Layout.preferredHeight: 13 }
        MText { text: parent.text; color: root.muted; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
    }
    component SkeletonLine: Rectangle {
        id: skeleton
        implicitWidth: 100; implicitHeight: 12; radius: Math.min(6,height/2); color: root.track
        opacity: 0.6; Accessible.ignored: true
        SequentialAnimation on opacity {
            running: skeleton.visible && (root.opened || root.settingsOpen) && prefs.motionStyle !== "reduced"
            loops: Animation.Infinite
            NumberAnimation { from: 0.35; to: 0.8; duration: Math.max(600,root.motionDuration(2.6)); easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.8; to: 0.35; duration: Math.max(600,root.motionDuration(2.6)); easing.type: Easing.InOutSine }
        }
    }
    component MText: Text { font.family: root.sans; color: root.foreground; font.pixelSize: 14; renderType: Text.QtRendering }
    component QuotaHint: ToolTip {
        id: hint
        popupType: Popup.Item
        delay: 240; timeout: 5000
        padding: 9
        implicitWidth: Math.min(280,implicitContentWidth + leftPadding + rightPadding)
        transformOrigin: Popup.Bottom
        contentItem: MText { text: hint.text; font.pixelSize: 11; color: root.foreground; wrapMode: Text.WordWrap; textFormat: Text.PlainText }
        background: Rectangle { color: root.track; radius: 10 }
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.controlDuration(); easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: root.controlDuration(); easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: root.controlDuration(); easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; to: 0.96; duration: root.controlDuration(); easing.type: Easing.InCubic }
            }
        }
    }
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
            border.width: positionButton.visualFocus ? 2 : 0; border.color: root.foreground
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
        property bool busy: false
        implicitWidth: 44; implicitHeight: 44
        enabled: !busy
        hoverEnabled: true; focusPolicy: Qt.StrongFocus
        Accessible.name: glyph === "refresh" ? "Refresh local view" : "Settings"
        contentItem: Item {
            LineIcon { anchors.centerIn: parent; width: 20; height: 20; name: button.glyph; visible: !button.busy }
            LoadingIndicator { anchors.centerIn: parent; width: 18; height: 18; active: button.busy }
        }
        background: Rectangle {
            radius: button.down ? 14 : button.hovered ? 16 : 22
            color: button.hovered ? root.track : root.buttonColor
            border.width: button.visualFocus ? 2 : 0; border.color: root.primary
            Behavior on radius { NumberAnimation { duration: root.controlDuration(); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: root.controlDuration() } }
        }
        ToolTip.visible: hovered; ToolTip.text: Accessible.name; ToolTip.delay: 450
    }
    component MSwitch: Switch {
        id: control
        property bool quietOutline: false
        implicitHeight: 36
        indicator: Rectangle {
            implicitWidth: 48; implicitHeight: 28
            x: control.leftPadding; y: (control.height - height) / 2
            radius: 14; color: control.checked ? root.primary : root.track
            border.width: control.visualFocus ? 2 : control.checked || control.quietOutline ? 0 : 1; border.color: control.visualFocus ? root.primary : root.outline
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
    function show() { if (!canOpenDrawer) return; closeTimer.stop(); opened = true }
    function hide() { pinned = false; opened = false; closeTimer.stop() }
    Timer { id: closeTimer; interval: prefs.dismissDelay; onTriggered: if (!root.settingsOpen && !root.pinned && !drawerHover.hovered) root.hide() }
    Process {
        id: reader
        onExited: (code, status) => { if (code !== 0) { root.cacheReady=true; root.status="Cache unavailable" } }
        command: [Quickshell.env("HOME") + "/.local/bin/aether", "usage"]
        stdout: StdioCollector { onStreamFinished: {
            try { let data = JSON.parse(text); root.cacheReady = true; let snapshot = JSON.stringify(data.accounts || []); if (snapshot !== root.accountSnapshot) { root.accountSnapshot = snapshot; root.allAccounts = data.accounts || [] } root.status = data.updated ? "Updated " + Qt.formatTime(new Date(data.updated * 1000), "HH:mm") : "No cached data" }
            catch(e) { root.cacheReady = true; root.status = "Cache unavailable" }
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
        function summary(): string {
            return JSON.stringify({viewMode:prefs.viewMode,colorScheme:prefs.colorScheme,fontChoice:prefs.fontChoice,motionRevision:prefs.motionRevision,hotspotRevision:prefs.hotspotRevision,opened:root.opened,settingsOpen:root.settingsOpen,hideUnavailable:prefs.hideUnavailableAccounts,usageReady:root.usageReady,visibleAccounts:root.accounts.length,totalAccounts:root.allAccounts.length,
                services:root.overviewAccountGroups.map(group => ({provider:group.provider,rows:group.rows.map(row => row.map(item => root.authLabel(item.account)))})),
                usageClients:root.overviewClients.map(client => ({provider:client.provider,tokens:client.totals.totalTokens,complete:client.totals.tokensComplete !== false}))})
        }
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
        implicitWidth: Math.min(prefs.layoutWidth + 12, screen ? screen.width : 372)
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
            radius: Math.min(24,width/2,height/2)
            color: root.surface
            transform: Scale {
                origin.x: body.width * root.ax; origin.y: body.height * root.ay
                xScale: 1 + root.drawerBounce(drawerSpring.value); yScale: xScale
            }

            clip: true
            // The content is always measured at the FINAL width. No text
            // reflow, scale, or layout resizing during the reveal.
            Flickable {
                id: scroll
                x: root.finalPanelX + 16 - body.x
                y: root.finalPanelY + 16 - body.y
                width: Math.max(1, drawer.width - 44)
                height: Math.max(1, root.panelHeight - 32)
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
                    width: scroll.width; spacing: 12
                    RowLayout {
                        id: heading
                        opacity: root.stagger(0)
                        enabled: opacity > 0.5
                        transform: Translate { y: (1 - heading.opacity) * 4 }
                        Layout.fillWidth: true; spacing: 6
                        WispMark { Layout.preferredWidth: 28; Layout.preferredHeight: 28; surfaceActive: root.opened }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 4
                            MText { text: "aether.ai"; font.pixelSize: 26; font.weight: Font.DemiBold; font.letterSpacing: -1; Layout.fillWidth: true; elide: Text.ElideRight }
                            MText { text: "AI resource monitor"; color: root.muted; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                        MButton { implicitWidth: 36; implicitHeight: 36; glyph: "refresh"; busy: root.localDataLoading; Layout.alignment: Qt.AlignVCenter; onClicked: root.refreshView() }
                        MButton { implicitWidth: 36; implicitHeight: 36; Layout.alignment: Qt.AlignVCenter; onClicked: { root.settingsOpen = true; root.hide() } }
                    }
                    RowLayout {
                        id: sectionHeading
                        opacity: root.stagger(1)
                        transform: Translate { y: (1 - sectionHeading.opacity) * 4 }
                        Layout.fillWidth: true
                        MText { text: "ACCOUNTS · REMAINING QUOTA"; color: root.muted; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.6; Layout.fillWidth: true }
                        MText { text: (root.accounts.length < 10 ? "0" : "") + root.accounts.length; color: root.muted; font.pixelSize: 12; font.family: root.monoFont }
                    }
                    LoadingStatus { Layout.fillWidth: true; visible: !root.cacheReady; active: root.cacheLoading; text: "Reading cached accounts…"; opacity: root.stagger(1) }
                    MText { opacity: root.stagger(2); visible: root.cacheReady && root.accounts.length === 0; text: prefs.hideUnavailableAccounts && root.allAccounts.length ? "No available accounts. Change visibility in Providers settings." : "No cached accounts. Run aether refresh."; color: root.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Repeater {
                        model: root.drawerRows
                        delegate: GridLayout {
                            id: drawerRow
                            required property var modelData
                            Layout.fillWidth: true; columnSpacing: 10; rowSpacing: 10
                            columns: root.rings ? modelData.length : 1
                            uniformCellWidths: true; uniformCellHeights: true
                            Repeater {
                                model: drawerRow.modelData
                                delegate: Loader {
                                    id: accountLoader
                                    required property string modelData
                                    property var account: root.accounts.find(a => String(a.id) === modelData) || ({id:modelData,provider:"",name:"",windows:[]})
                                    property int accountIndex: root.drawerAccountIds.indexOf(modelData)
                                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: 0; Layout.preferredWidth: 1
                                    Layout.preferredHeight: item ? item.implicitHeight : 0
                                    sourceComponent: root.compactAccount(account) ? usageDelegate : root.rings ? ringDelegate : quotaDelegate
                                    Component { id: quotaDelegate; DrawerQuotaCard { modelData: accountLoader.account; index: accountLoader.accountIndex } }
                                    Component { id: ringDelegate; DrawerRingCard { modelData: accountLoader.modelData; index: accountLoader.accountIndex } }
                                    Component { id: usageDelegate; DrawerUsageCard { modelData: accountLoader.account; index: accountLoader.accountIndex } }
                                }
                            }
                        }
                    }
                    RowLayout {
                        id: footer
                        opacity: root.stagger(root.drawerStages.footer)
                        transform: Translate { y: (1 - footer.opacity) * 4 }
                        Layout.fillWidth: true; spacing: 6
                        LoadingIndicator { Layout.preferredWidth: 12; Layout.preferredHeight: 12; active: root.localDataLoading; visible: active }
                        Rectangle { visible: !root.localDataLoading; Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: root.muted }
                        MText { text: root.localDataLoading ? root.loadingMessage : root.analyticsError ? "Usage refresh failed" : "Local cache"; color: root.muted; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                        Item { Layout.fillWidth: true }
                        MText { text: root.status; color: root.muted; font.pixelSize: 11; elide: Text.ElideRight; Layout.maximumWidth: scroll.width * 0.52 }
                    }
                }
            }
            ScrollFade { anchors.fill: scroll; viewport: scroll }
        }
    }
    component DrawerQuotaCard: Rectangle {
        id: accountCard
        required property var modelData
        required property int index
        objectName: "drawer-account-" + (typeof modelData === "string" ? modelData : modelData.id)
        property int revealStage: root.drawerStages.accounts[index] || 2
        property int detailStage: revealStage + 2 + (modelData.status !== "ok" ? 1 : 0)
        opacity: root.stagger(revealStage)
        transform: Translate { y: (1 - accountCard.opacity) * 4 }
        Layout.fillWidth: true
        implicitHeight: card.implicitHeight + 28
        radius: prefs.cardRadius; color: root.cardColor
        ColumnLayout {
            id: card
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14
            spacing: 12
            RowLayout {
                id: accountHeading
                opacity: root.stagger(accountCard.revealStage + 1)
                transform: Translate { y: (1 - accountHeading.opacity) * 4 }
                Layout.fillWidth: true; spacing: 6
                Rectangle {
                    Layout.preferredWidth: 36; Layout.preferredHeight: 36
                    radius: 13; color: root.buttonColor
                    ProviderIcon { anchors.centerIn: parent; width: 20; height: 20; name: root.logo(accountCard.modelData.provider) }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 3
                    MText { text: accountCard.modelData.provider; font.weight: Font.DemiBold; font.pixelSize: 15; Layout.fillWidth: true; elide: Text.ElideRight }
                    MText { text: accountCard.modelData.name; color: root.muted; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                }
            }
            MText { opacity: root.stagger(accountCard.revealStage + 2); visible: accountCard.modelData.status !== "ok"; text: root.accountStatus(accountCard.modelData); color: root.danger; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            Repeater {
                model: accountCard.modelData.windows || []
                delegate: ColumnLayout {
                    required property var modelData
                    id: quota
                    property bool known: modelData.remaining !== null && modelData.remaining !== undefined && isFinite(Number(modelData.remaining))
                    property real remaining: known ? Math.max(0, Math.min(100, Number(modelData.remaining))) : 0
                    property color indicator: known && remaining < 20 ? root.danger : root.primary
                    required property int index
                    opacity: root.stagger(accountCard.detailStage + index)
                    transform: Translate { y: (1 - quota.opacity) * 4 }
                    MotionValue { id: quotaFill; targetValue: root.opened && quota.opacity > 0.15 ? 1 : 0; dataMotion: true; animateInitial: quota.opacity < 1; factor: 0.75; curve: Easing.InOutCubic }
                    Layout.fillWidth: true; spacing: 6
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        MText { text: root.windowLabel(quota.modelData); font.pixelSize: 12; font.weight: Font.Medium; Layout.fillWidth: true }
                        MText { text: root.windowValue(quota.modelData); color: quota.indicator; font.family: root.monoFont; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignRight }
                    }
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 6; radius: 3; color: root.track
                        Rectangle { property real displayedQuota: quota.remaining; Behavior on displayedQuota { NumberAnimation { duration: root.dataDuration(0.75); easing.type: Easing.InOutCubic } } width: parent.width * displayedQuota / 100 * quotaFill.value; height: parent.height; radius: Math.min(4, width / 2); color: quota.indicator }
                    }
                    MText { text: quota.known ? root.resetText(quota.modelData.reset) : "Quota unavailable"; color: root.muted; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                }
            }
        }
    }
    component DrawerRingCard: Rectangle {
        id: ringCard
        required property var modelData
        required property int index
        property var account: root.quotaAccounts.find(a => String(a.id) === String(modelData)) || ({name:"",provider:"",windows:[],status:"ok"})
        objectName: "drawer-account-" + (typeof modelData === "string" ? modelData : modelData.id)
        property int revealStage: root.drawerStages.accounts[index] || 2
        property var session: root.windowFor(account, 300)
        property var week: root.windowFor(account, 10080)
        property real sessionLeft: root.remaining(session)
        property real weekLeft: root.remaining(week)
        property real sessionSweep: Math.max(0, sessionLeft)
        property real weekSweep: Math.max(0, weekLeft)
        Behavior on sessionSweep { enabled: root.opened && prefs.motionStyle !== "reduced"; NumberAnimation { duration: root.dataDuration(0.75); easing.type: Easing.Linear } }
        Behavior on weekSweep { enabled: root.opened && prefs.motionStyle !== "reduced"; NumberAnimation { duration: root.dataDuration(0.75); easing.type: Easing.Linear } }
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: 132
        implicitHeight: ringContent.implicitHeight + 20
        radius: prefs.cardRadius; color: root.cardColor
        opacity: root.stagger(revealStage)
        transform: Translate { y: (1 - ringCard.opacity) * 4 }
        ColumnLayout {
            id: ringContent
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: 10; spacing: 4
            RowLayout {
                id: ringHeading
                opacity: root.stagger(ringCard.revealStage + 1)
                transform: Translate { y: (1 - ringHeading.opacity) * 4 }
                Layout.fillWidth: true; spacing: 6
                ProviderIcon { Layout.preferredWidth: 23; Layout.preferredHeight: 23; name: root.logo(ringCard.account.provider) }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                    MText { Layout.fillWidth: true; elide: Text.ElideRight; text: ringCard.account.name; font.weight: Font.DemiBold; font.pixelSize: 12 }
                    MText { Layout.fillWidth: true; elide: Text.ElideRight; text: ringCard.account.provider; color: root.muted; font.pixelSize: 10 }
                }
            }
            Item {
                id: ringFace
                opacity: root.stagger(ringCard.revealStage + 2)
                // Never let the layout independently stretch the two axes.
                property real diameter: Math.max(1, Math.min(root.quotaAccounts.length === 1 ? 124 : 116, Math.floor(ringCard.width - 20)))
                property real strokeSize: diameter * 0.05
                property real outerRadius: diameter * 0.40
                property real innerRadius: diameter * (37 / 120)
                MotionValue { id: ringFill; targetValue: root.opened && ringFace.visible && ringFace.opacity > 0.15 ? 1 : 0; dataMotion: true; animateInitial: true; factor: 0.8; curve: Easing.Linear }
                property real drawProgress: ringFill.value
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
                    id: weeklyCentre
                    anchors.centerIn: parent
                    width: Math.floor(ringFace.diameter * 0.43)
                    spacing: Math.max(1, Math.round(ringFace.diameter * 0.012))
                    HoverHandler { id: weeklyResetHover }
                    QuotaHint {
                        id: weeklyResetPeek
                        parent: weeklyCentre
                        visible: root.opened && weeklyResetHover.hovered && ringFace.opacity > 0.99
                        text: root.resetText(ringCard.week ? ringCard.week.reset : null)
                        x: (parent.width - width) / 2
                        y: -height - 8
                    }
                    MText {
                        width: parent.width; height: Math.max(1, Math.floor(ringFace.diameter * 0.19))
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: ringCard.weekLeft < 0 ? "—" : Math.round(ringCard.weekLeft) + "%"
                        font.weight: Font.DemiBold
                        font.pixelSize: Math.max(6, Math.floor(ringFace.diameter * 0.17))
                        minimumPixelSize: 4; fontSizeMode: Text.Fit
                        wrapMode: Text.NoWrap; color: root.foreground
                    }
                    MText {
                        width: parent.width; height: Math.max(1, Math.floor(ringFace.diameter * 0.105))
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: "Weekly"; font.pixelSize: Math.max(6, Math.floor(ringFace.diameter * 0.078))
                        minimumPixelSize: 4; fontSizeMode: Text.Fit; wrapMode: Text.NoWrap; color: root.muted
                    }
                }
            }
            // Align labels and values like the website preview; keep
            // reset text subordinate rather than splitting it into a third row.
            Repeater {
                model: [
                    { label: "Session", value: ringCard.sessionLeft, quota: ringCard.session, tint: root.sessionColor }
                ].concat(root.extraWindows(ringCard.account).map(w => ({label:root.windowLabel(w),value:root.remaining(w),quota:w,tint:root.weeklyColor})))
                delegate: RowLayout {
                    required property var modelData
                    required property int index
                    opacity: root.stagger(ringCard.revealStage + 3 + index)
                    Layout.fillWidth: true; spacing: 6
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                        MText { Layout.fillWidth: true; text: modelData.label; color: root.muted; font.pixelSize: 11; elide: Text.ElideRight }
                        MText {
                            visible: modelData.quota !== null
                            Layout.fillWidth: true; font.pixelSize: 10; color: root.muted; elide: Text.ElideRight
                            text: root.resetText(modelData.quota ? modelData.quota.reset : null) + (modelData.quota && modelData.quota.shared ? " · Shared budget" : "")
                        }
                    }
                    MText {
                        text: modelData.quota ? root.windowValue(modelData.quota) : "—"
                        color: modelData.tint; font.family: root.monoFont; font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
            MText { opacity: root.stagger(ringCard.revealStage + 4 + root.extraWindows(ringCard.account).length); visible: ringCard.account.status !== "ok"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: root.danger; font.pixelSize: 11; wrapMode: Text.WordWrap; text: root.accountStatus(ringCard.account) }
        }
    }
    component DrawerUsageCard: Rectangle {
        id: apiKeyCard
        required property var modelData
        required property int index
        objectName: "drawer-account-" + (typeof modelData === "string" ? modelData : modelData.id)
        property int revealStage: root.drawerStages.accounts[index] || 2
        Layout.fillWidth: true
        implicitHeight: compactContent.implicitHeight + 26
        radius: Math.min(18,prefs.cardRadius); color: root.cardColor
        opacity: root.stagger(revealStage)
        transform: Translate { y: (1 - apiKeyCard.opacity) * 4 }
        ColumnLayout {
            id: compactContent
            anchors.fill: parent; anchors.margins: 13
            spacing: 8
            RowLayout {
                id: apiKeyDetails
                Layout.fillWidth: true
                spacing: 7
                ProviderIcon {
                    Layout.preferredWidth: 22; Layout.preferredHeight: 22
                    name: root.logo(apiKeyCard.modelData.provider)
                    opacity: root.stagger(apiKeyCard.revealStage + 1)
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 3
                    opacity: root.stagger(apiKeyCard.revealStage + 1)
                    MText { text: apiKeyCard.width < 240 ? apiKeyCard.modelData.name : apiKeyCard.modelData.provider; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                    MText { text: apiKeyCard.width < 240 ? apiKeyCard.modelData.provider + (apiKeyCard.modelData.authKind === "free" ? " · " + root.compactValue(apiKeyCard.modelData) : root.authLabel(apiKeyCard.modelData) ? " · " + root.authLabel(apiKeyCard.modelData) : "") : apiKeyCard.modelData.name; font.pixelSize: 10; color: root.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                }
                ColumnLayout {
                    spacing: 3; opacity: root.stagger(apiKeyCard.revealStage + 2)
                    MText { visible: apiKeyCard.width >= 240 && text.length > 0; text: root.compactTitle(apiKeyCard.modelData); font.pixelSize: 11; font.weight: Font.Medium; color: root.foreground; Layout.alignment: Qt.AlignRight }
                    MText { visible: apiKeyCard.width >= 240; text: root.compactValue(apiKeyCard.modelData); font.pixelSize: 10; color: root.muted; Layout.alignment: Qt.AlignRight }
                }
            }
            AccountUsageReading {
                visible: !(apiKeyCard.modelData.windows || []).length && (!root.usageReady || root.hasUsageData(root.accountUsage(apiKeyCard.modelData)))
                account: apiKeyCard.modelData; compact: true; monitor: true
                Layout.fillHeight: true
                opacity: root.stagger(apiKeyCard.revealStage + 2)
            }
            Repeater {
                model: apiKeyCard.modelData.windows || []
                delegate: ColumnLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true; spacing: 4
                    opacity: root.stagger(apiKeyCard.revealStage + 3 + index)
                    RowLayout {
                        Layout.fillWidth: true
                        MText { text: root.windowLabel(modelData); font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                        MText { text: root.windowValue(modelData); font.pixelSize: 11; font.family: root.monoFont }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 4; radius: 2; color: root.track
                        Rectangle { width: parent.width * Math.max(0,root.remaining(modelData))/100; height: parent.height; radius: 2; color: root.primary }
                    }
                    MText { text: root.resetText(modelData.reset) + (modelData.shared ? " · Shared budget" : ""); font.pixelSize: 10; color: root.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                }
            }
        }
        HoverHandler { id: compactHover }
        QuotaHint { parent: apiKeyCard; visible: root.opened && compactHover.hovered && apiKeyCard.modelData.authKind === "free"; text: root.compactHint(apiKeyCard.modelData); y: -height - 8; x: (parent.width-width)/2 }
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
        Rectangle {
            anchors.fill: parent; radius: choice.radius
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
            border.color: liquidSelect.visualFocus || liquidSelect.popup.visible ? root.primary : root.outline
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
                    radius: Math.min(20,width/2,height/2)
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
    component AccountUsageReading: ColumnLayout {
        id: accountReading
        required property var account
        property bool compact: false
        property bool monitor: false
        property bool narrow: compact && width < 220
        property var usage: root.accountUsage(account)
        Layout.fillWidth: true; spacing: 7
        GridLayout {
            visible: !!accountReading.usage.available
            columns: accountReading.narrow ? 1 : 2; Layout.fillWidth: true; Layout.fillHeight: accountReading.monitor; columnSpacing: 16; rowSpacing: accountReading.monitor ? 16 : 8
            Repeater {
                model: [{value:root.countText((accountReading.usage.totals || {}).totalTokens),label:(accountReading.usage.totals || {}).tokensComplete === false ? "Known tokens" : "Tokens"}, {value:root.usageCost(accountReading.usage.totals || {}),label:(accountReading.usage.totals || {}).costComplete === false ? "Known cost" : "Usage cost"}]
                delegate: GridLayout {
                    required property var modelData
                    columns: 1; Layout.fillWidth: true; Layout.fillHeight: accountReading.monitor; columnSpacing: 6; rowSpacing: 4
                    Item { visible: accountReading.monitor; Layout.fillHeight: true }
                    MText { objectName: "usage-value"; text: modelData.value; font.pixelSize: accountReading.monitor ? (accountReading.narrow ? 23 : 26) : accountReading.compact ? 22 : 24; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                    MText { text: modelData.label; font.pixelSize: 11; color: root.muted; Layout.fillWidth: true }
                    Item { visible: accountReading.monitor; Layout.fillHeight: true }
                }
            }
        }
        ColumnLayout {
            visible: !accountReading.usage.available && !root.usageReady
            Layout.fillWidth: true; spacing: 7
            SkeletonLine { Layout.fillWidth: true; implicitHeight: 15 }
            SkeletonLine { Layout.preferredWidth: parent.width*0.65; implicitHeight: 9 }
        }
        MText {
            visible: !!accountReading.usage.available && !accountReading.monitor
            text: (accountReading.usage.periodDays===7 ? "Last 7 days" : root.usagePeriodText)+" · "+(accountReading.usage.scope || "Local usage")+(accountReading.account.provider === "Claude Code" && (accountReading.usage.totals || {}).tokensComplete === false ? " · input and cache only" : "")+(accountReading.usage.partial ? " · partial" : "")
            font.pixelSize: 10; color: root.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap
        }
        MText {
            visible: !accountReading.usage.available && root.usageReady
            text: root.analyticsError ? "Local usage unavailable." : "No local usage recorded for this period."
            font.pixelSize: 11; color: root.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap
        }
    }
    component OverviewAccountCard: Rectangle {
        id: overviewAccount
        required property var account
        required property var usage
        property bool sharedUsage: false
        property bool hasLimits: (account.windows || []).length>0
        property bool hasData: hasLimits || root.hasUsageData(usage)
        Layout.fillWidth: true; Layout.fillHeight: true
        implicitHeight: Math.max(sharedUsage ? 64 : hasLimits ? 140 : 88,overviewDetails.implicitHeight+24); radius: 18; color: root.cardColor
        ColumnLayout {
            id: overviewDetails
            anchors.fill: parent; anchors.margins: 12; spacing: 8
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                ProviderIcon { name: root.logo(overviewAccount.account.provider); Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                MText { text: overviewAccount.account.name; font.weight: Font.Medium; font.pixelSize: 14; Layout.fillWidth: true; elide: Text.ElideRight }
                MText { text: root.authLabel(overviewAccount.account); color: root.muted; font.pixelSize: 10 }
            }
            MText {
                text: !root.usageReady ? root.accountSummary(overviewAccount.account) : !overviewAccount.hasData ? (overviewAccount.account.status === "login_required" ? "Sign in again for limits" : "No local usage or limits") : root.accountSummary(overviewAccount.account)
                font.pixelSize: 11; color: root.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
            GridLayout {
                visible: overviewAccount.hasLimits; columns: overviewAccount.width>=220 ? 2 : 1
                Layout.fillWidth: true; columnSpacing: 14; rowSpacing: 9
                Repeater {
                    model: overviewAccount.account.windows || []
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: 5
                        RowLayout {
                            Layout.fillWidth: true
                            MText { text: modelData.minutes===300 ? "Session" : root.windowLabel(modelData); font.pixelSize: 11; color: root.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                            MText { text: root.windowValue(modelData); font.pixelSize: 11 }
                        }
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: 4; radius: 2; color: root.track
                            Rectangle { width: parent.width*Math.max(0,root.remaining(modelData))/100*root.pageDataProgress(3); height: parent.height; radius: 2; color: root.primary }
                        }
                        MText { text: root.resetText(modelData.reset); font.pixelSize: 10; color: root.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }
            }
            Item { Layout.fillHeight: true }
            AccountUsageReading { visible: !overviewAccount.sharedUsage && (root.hasUsageData(overviewAccount.usage) || !overviewAccount.hasLimits || !root.usageReady); account: overviewAccount.account; usage: overviewAccount.usage; compact: true }

        }
    }
    component OverviewAccountGroup: ColumnLayout {
        id: accountGroup
        required property var group
        property int revealIndex: 0
        Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: 10
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            ProviderIcon { name: root.logo(accountGroup.group.provider); Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
            MText { text: accountGroup.group.provider; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
        }
        Repeater {
            model: accountGroup.group.sharedUsage
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 5
                RowLayout {
                    Layout.fillWidth: true
                    MText { text: root.countText(modelData.totals.totalTokens)+" tokens"; font.pixelSize: 17; font.weight: Font.Medium; Layout.fillWidth: true }
                    MText { text: root.usageCost(modelData.totals); font.pixelSize: 17 }
                }
                MText { text: modelData.scope+" · counted once"; font.pixelSize: 11; color: root.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
        }
        Repeater {
            model: accountGroup.group.rows
            delegate: GridLayout {
                id: accountRow
                required property var modelData
                required property int index
                opacity: root.pageStage(accountGroup.revealIndex + index + 4)
                transform: Translate { y: 8 * (1 - accountRow.opacity) }
                columns: accountGroup.width>=440 ? modelData.length : 1
                uniformCellWidths: true; uniformCellHeights: true
                Layout.fillWidth: true; columnSpacing: 12; rowSpacing: 12
                Repeater {
                    model: accountRow.modelData
                    delegate: OverviewAccountCard {
                        required property var modelData
                        account: modelData.account; usage: modelData.usage
                        sharedUsage: accountGroup.group.sharedKeys.includes(modelData.usage.sourceKey)
                    }
                }
            }
        }
    }

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
            anchors.alignWhenCentered: false
            width: 40 + (settingsPanel.width-40)*root.settingsReveal
            height: 40 + (settingsPanel.height-40)*root.settingsReveal
            transform: Scale { origin.x: settingsBody.width/2; origin.y: settingsBody.height/2; xScale: 1+root.surfaceBounce(settingsSpring.value,settingsPanel.width,settingsPanel.height); yScale: xScale }
            radius: Math.min(30,width/2,height/2); color: root.surface

            clip: true
            opacity: root.smooth(settingsSpring.value / 0.14)
            visible: root.settingsOpen || settingsSpring.value > 0.0001
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
                anchors.alignWhenCentered: false
                width: Math.max(1,settingsPanel.width-24); height: Math.max(1,settingsPanel.height-24)
                opacity: root.settingsContentReveal
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
                                            border.width: navigationButton.visualFocus ? 2 : 0; border.color: root.foreground
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
                            property bool usagePage: ["Overview","Providers","Analytics"].includes(root.settingsTab)
                            Layout.fillWidth: true; implicitHeight: headingLabel.implicitHeight + (usagePage ? 22 : 0)
                            MText {
                                id: headingLabel; text: root.settingsTab; width: pageHeading.width
                                font.pixelSize: 31; font.weight: Font.DemiBold; font.letterSpacing: -1; elide: Text.ElideRight
                                opacity: root.pageStage(0)
                                transform: ItemGrowth { stage: root.pageStage(0) }
                            }
                            LoadingStatus { anchors.left: parent.left; anchors.right: parent.right; anchors.top: headingLabel.bottom; anchors.topMargin: 4; visible: pageHeading.usagePage; active: root.localDataLoading; text: root.loadingMessage; opacity: root.pageStage(0) }
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
                                id: overviewPage
                                visible: root.settingsTab === "Overview"; Layout.fillWidth: true; spacing: 16
                                RowLayout {
                                    opacity: root.pageStage(1); Layout.fillWidth: true; spacing: 14
                                    WispMark { Layout.preferredWidth: 64; Layout.preferredHeight: 72; ink: root.primary }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 5
                                        MText { text: root.overviewHeading; font.pixelSize: 23; font.weight: Font.DemiBold; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                        Description { text: root.quotaAccountCount+" reporting limits"+(root.usageReady ? " · "+root.overviewClients.length+" with local usage" : ""); font.pixelSize: 12 }
                                        MText { visible: root.attentionAccountCount>0; text: root.attentionAccountCount+" "+(root.attentionAccountCount===1?"account needs":"accounts need")+" attention"; color: root.primary; font.pixelSize: 12; Layout.fillWidth: true }
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true; spacing: 8; opacity: root.pageStage(2)
                                    Repeater { model: [{v:"1",n:"24 hours"},{v:"7",n:"7 days"},{v:"30",n:"30 days"}]
                                        delegate: Choice { required property var modelData; label: modelData.n; selected: root.analyticsPeriod===modelData.v; onChosen: root.analyticsPeriod=modelData.v }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true; implicitHeight: overviewMetrics.implicitHeight+32
                                    radius: 22; color: root.cardColor; opacity: root.pageStage(3)
                                    ColumnLayout {
                                        id: overviewMetrics
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 16; spacing: 16
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 16
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 4
                                                Description { text: root.overviewTotals.tokensComplete ? "Tokens" : "Known tokens"; font.pixelSize: 12 }
                                                Item { Layout.fillWidth: true; implicitHeight: 46; MText { visible: root.usageReady; text: root.overviewClients.length ? root.countText(root.overviewTotals.totalTokens*root.pageDataProgress(0)) : "—"; font.pixelSize: 38; font.weight: Font.DemiBold; font.letterSpacing: -1; width: parent.width; elide: Text.ElideRight } SkeletonLine { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: Math.min(parent.width*0.72,150); height: 26; visible: !root.usageReady } }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 4
                                                Description { text: root.overviewTotals.costComplete ? "Usage cost" : "Known usage cost"; font.pixelSize: 12 }
                                                Item { Layout.fillWidth: true; implicitHeight: 46; MText { visible: root.usageReady; text: root.overviewClients.length ? root.usageCost(root.overviewTotals) : "—"; font.pixelSize: 32; font.weight: Font.DemiBold; font.letterSpacing: -1; width: parent.width; elide: Text.ElideRight } SkeletonLine { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: Math.min(parent.width*0.72,150); height: 26; visible: !root.usageReady } }
                                            }
                                        }
                                        Flow {
                                            Layout.fillWidth: true; spacing: 14
                                            MText { opacity: root.usageReady ? 1 : 0; text: root.countText(root.overviewTotals.inputTokens)+" input"; font.pixelSize: 12; color: root.muted }
                                            MText { opacity: root.usageReady ? 1 : 0; text: root.overviewTotals.tokensComplete ? root.countText(root.overviewTotals.outputTokens)+" output" : "Output partly unavailable"; font.pixelSize: 12; color: root.muted }
                                            MText { opacity: root.usageReady ? 1 : 0; text: root.countText(root.overviewTotals.cachedInputTokens)+" cached"; font.pixelSize: 12; color: root.muted }
                                        }
                                        Description { visible: root.usageReady; text: root.overviewClients.length ? "Recorded and estimated costs. Not a bill." : "No local usage recorded for this period."; font.pixelSize: 11 }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    SectionTitle { text: "Accounts" }
                                    Choice { label: "Usage details"; onChosen: root.selectPage("Analytics") }
                                }
                                Repeater {
                                    model: root.overviewAccountGroups
                                    delegate: OverviewAccountGroup {
                                        required property var modelData
                                        required property int index
                                        group: modelData; revealIndex: index
                                        opacity: root.pageStage(index+4)
                                        transform: Translate { y: 8 * (1 - root.pageStage(index+4)) }
                                    }
                                }
                                Description { visible: !root.accounts.length; text: "No visible accounts. Check provider preferences." }
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
                                    text: "Smooth uses gradual expansion and staggered reveals. Data fills have independent timing. Reduced disables animations." }
                                RowLayout { opacity: root.pageStage(20); transform: ItemGrowth { stage: root.pageStage(20) }
                                    
                                    Layout.fillWidth: true
                                    MText { text: "Motion style"; Layout.fillWidth: true }
                                    LiquidSelect { Layout.preferredWidth: 180; model: ["Smooth","Reduced"]; currentIndex: Math.max(0,["smooth","reduced"].indexOf(prefs.motionStyle)); onActivated: function(index) { prefs.motionStyle = ["smooth","reduced"][index] }}
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
                                RowLayout {
                                    Layout.fillWidth: true
                                    MText { text: "Hide unavailable accounts"; Layout.fillWidth: true }
                                    MSwitch { quietOutline: true; checked: prefs.hideUnavailableAccounts; Accessible.name: "Hide unavailable accounts"; onToggled: { prefs.hideUnavailableAccounts=checked; prefs.sync() } }
                                }
                                Description { text: "Keep accounts with limits or recorded usage. All discovered accounts remain manageable below."; font.pixelSize: 11 }
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
                                                ProviderIcon { Layout.preferredWidth: 38; Layout.preferredHeight: 38; name: providerRow.modelData.id }
                                                ColumnLayout { Layout.fillWidth: true; spacing: 3
                                                    MText { text: providerRow.modelData.name; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                                    Description { text: providerRow.matches.length ? providerRow.matches.filter(a => !root.hiddenAccounts.includes(String(a.id))).length + " of " + providerRow.matches.length + " accounts selected" : ["codex","claude","pi","opencode"].includes(providerRow.modelData.id) ? "No accounts discovered. Sign in through the client." : "Quota adapter unavailable"; font.pixelSize: 11 }
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
                                                    radius: 16; color: root.surface
                                                    opacity: (providerRow.shown ? 1 : 0.55)*root.pageStage(providerRow.index+3+index)
                                                    transform: ItemGrowth { stage: root.pageStage(providerRow.index+3+index) }
                                                    ColumnLayout {
                                                        id: accountDetails
                                                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 12; spacing: 10
                                                        RowLayout {
                                                            Layout.fillWidth: true; spacing: 10
                                                            Rectangle {
                                                                Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: 12; color: root.buttonColor
                                                                ProviderIcon { anchors.centerIn: parent; width: 22; height: 22; name: root.logo(accountRow.modelData.provider) }
                                                            }
                                                            ColumnLayout {
                                                                Layout.fillWidth: true; spacing: 3
                                                                MText { text: accountRow.modelData.name || "Account"; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                                                RowLayout {
                                                                    spacing: 5
                                                                    Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: ["ok","free_available"].includes(accountRow.modelData.status) ? root.primary : accountRow.modelData.status === "stale" ? root.weeklyColor : root.danger }
                                                                    MText { text: !accountRow.shown || !providerRow.shown ? "Hidden" : accountRow.modelData.status === "ok" ? "Available" : accountRow.modelData.status === "stale" ? "Stale cache" : accountRow.modelData.authKind === "free" ? root.compactValue(accountRow.modelData) : root.accountSummary(accountRow.modelData); font.pixelSize: 11; color: root.muted }
                                                                }
                                                            }
                                                            MSwitch { enabled: providerRow.shown; checked: accountRow.shown; onToggled: root.setHidden("hiddenAccounts", String(accountRow.modelData.id), !checked) }
                                                        }
                                                        RowLayout {
                                                            visible: !!root.windowFor(accountRow.modelData,300) || !!root.windowFor(accountRow.modelData,10080)
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
                                                        Repeater {
                                                            model: root.extraWindows(accountRow.modelData)
                                                            delegate: RowLayout {
                                                                required property var modelData
                                                                Layout.fillWidth: true
                                                                Description { text: root.windowLabel(modelData); font.pixelSize: 11 }
                                                                MText { text: root.windowValue(modelData); font.pixelSize: 11; font.family: root.monoFont }
                                                            }
                                                        }
                                                        AccountUsageReading { account: accountRow.modelData; compact: true }
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
                                    text: "OpenCode usage is device-wide. Codex usage follows each local account. Costs can include model-price estimates." }
                                Flow {
                                    Layout.fillWidth: true; spacing: 8
                                    Repeater { model: [{v:"1",n:"24 hours"},{v:"7",n:"7 days"},{v:"30",n:"30 days"},{v:"90",n:"90 days"}]
                                        delegate: Choice { required property var modelData; required property int index; opacity: root.pageStage(2+index); transform: ItemGrowth { stage: root.pageStage(2+index) } label: modelData.n; selected: root.analyticsPeriod === modelData.v; onChosen: root.analyticsPeriod = modelData.v }
                                    }
                                }
                                ColumnLayout {
                                    id: openCodeUsage
                                    visible: !root.hiddenProviders.includes("opencode") && root.openCodeAnalytics.status !== "not_detected"
                                    Layout.fillWidth: true; spacing: 12
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        ProviderIcon { name: "opencode"; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                                        SectionTitle { text: "OpenCode" }
                                    }
                                    Description { visible: root.openCodeAnalytics.status !== "ok"; text: root.openCodeAnalytics.status === "loading" ? "Reading local OpenCode usage…" : "Local usage unavailable. Open OpenCode and refresh." }
                                    GridLayout {
                                        visible: root.openCodeAnalytics.status === "ok"
                                        columns: Math.max(1,Math.min(3,Math.floor((pageScroll.width+12)/180)))
                                        Layout.fillWidth: true; columnSpacing: 12; rowSpacing: 12
                                        StatCard { label: "Tokens"; value: root.countText((root.openCodeAnalytics.totals || {}).totalTokens) }
                                        StatCard { label: "Model steps"; value: root.countText((root.openCodeAnalytics.totals || {}).steps) }
                                        StatCard { label: "Recorded cost"; value: root.usageCost(root.openCodeAnalytics.totals || {}) }
                                    }
                                    Description { visible: root.openCodeAnalytics.status === "ok"; text: "All models used through OpenCode on this device. Recorded costs can be endpoint charges or catalogue estimates."; font.pixelSize: 11 }
                                    Repeater {
                                        model: root.openCodeAnalytics.status === "ok" ? root.openCodeModels : []
                                        delegate: ColumnLayout {
                                            required property var modelData
                                            Layout.fillWidth: true; spacing: 3
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 10
                                                MText { text: root.openCodeModelName(modelData); Layout.fillWidth: true; elide: Text.ElideRight; font.weight: Font.Medium }
                                                MText { text: root.usageCost(modelData); font.pixelSize: 12 }
                                            }
                                            MText { text: modelData.providerID + " · " + root.countText(modelData.steps) + " steps · " + root.countText(modelData.totalTokens) + " tokens"; font.pixelSize: 11; color: root.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                            MText { text: root.countText(modelData.inputTokens) + " input · " + root.countText(modelData.outputTokens) + " output · " + root.countText(modelData.cachedInputTokens) + " cached · " + root.countText(modelData.reasoningTokens) + " reasoning"; font.pixelSize: 10; color: root.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                            MText { visible: !!root.openCodeObservation(modelData).observation && !!root.openCodeObservation(modelData).observation.limitObservedAt; text: root.freeLimitText(root.openCodeObservation(modelData)); font.pixelSize: 11; color: root.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                        }
                                    }
                                    Description { visible: root.openCodeAnalytics.status === "ok" && root.openCodeModels.length === 0; text: "No model activity recorded in this period." }
                                    Description { visible: !!root.openCodeAnalytics.modelsTruncated; text: "Showing the first 256 models. Totals include all models."; font.pixelSize: 11 }
                                }
                                Repeater {
                                    model: root.clientUsage.filter(c => !root.hiddenProviders.includes(root.logo(c.provider)))
                                    delegate: ColumnLayout {
                                        required property var modelData
                                        Layout.fillWidth: true; spacing: 12
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            ProviderIcon { name: root.logo(modelData.provider); Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                                            SectionTitle { text: modelData.provider }
                                        }
                                        GridLayout {
                                            visible: modelData.status === "ok"
                                            columns: pageScroll.width>=520 ? 3 : 1; Layout.fillWidth: true; columnSpacing: 12; rowSpacing: 12
                                            StatCard { label: modelData.totals.tokensComplete === false ? "Known tokens" : "Tokens"; value: root.countText(modelData.totals.totalTokens) }
                                            StatCard { label: "Model steps"; value: root.countText(modelData.totals.steps) }
                                            StatCard { label: modelData.totals.costComplete === false ? "Known usage cost" : "Usage cost"; value: root.usageCost(modelData.totals) }
                                        }
                                        Description { text: modelData.status !== "ok" ? "No local usage recorded for this period." : modelData.provider === "Claude Code" && modelData.totals.tokensComplete === false ? "Input and cache totals from local transcripts. Final output counts are unavailable in these records." : modelData.partial ? "Partial local usage. One or more oversized or unreadable records were skipped." : "Local client usage on this device. Recorded costs can be estimates."; font.pixelSize: 11 }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    ProviderIcon { name: "codex"; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                                    SectionTitle { text: "Codex" }
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
                                    MText { text: "Open in fullscreen"; Layout.fillWidth: true } MSwitch { checked: prefs.fullscreenOverride; onToggled: prefs.fullscreenOverride = checked } }
                                Description { opacity: root.pageStage(3); transform: ItemGrowth { stage: root.pageStage(3) }
                                    text: "Off by default. Keep the monitor closed while an app is fullscreen. Enable to allow it over fullscreen apps." }
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
                                    label: "Restore defaults"; onChosen: { prefs.followTheme=true; prefs.colorScheme="mono"; prefs.hoverEnabled=true; prefs.fullscreenOverride=false; prefs.motionMs=240; prefs.dataMotionMs=450; prefs.dismissDelay=350; prefs.layoutWidth=360; prefs.cacheSeconds=5; prefs.viewMode="grid"; prefs.hotspot="top-right"; prefs.staggerEnabled=true; prefs.hiddenProviders="[]"; prefs.hiddenAccounts="[]"; prefs.hideUnavailableAccounts=false; prefs.chartMode="line"; prefs.hotspotSize=40; prefs.hotspotRevision=1; prefs.fontChoice="auto"; prefs.cardRadius=24; prefs.edgeFades=true; prefs.fadeDepth=28; prefs.localShortcutsEnabled=true; prefs.globalShortcutsEnabled=true; prefs.shortcutBindings="{}"; prefs.bindSyntax="conf"; prefs.motionStyle="smooth"; prefs.trackpadSpeed=1.6; prefs.wispMotion=true } }
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
