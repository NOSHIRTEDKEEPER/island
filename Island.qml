import Qt.labs.folderlistmodel
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "components"
import "file:///usr/share/omarchy/shell/plugins/clipboard/ClipboardHistory.js" as ClipboardHistory
import qs.Commons
import "views"

Item {
    id: root

    property var shell: null
    property var manifest: null
    property var pluginRegistry: null
    property var barWidgetRegistry: null
    property var bar: null
    property var barConfig: ({
    })
    property string omarchyPath: ""
    readonly property var media: shell ? shell.firstPartyServiceFor("omarchy.media") : null
    // Keep now-playing metadata available even when the Omarchy media proxy
    // has not selected an active player yet (common for browser MPRIS players).
    readonly property var directPlayer: {
        var players = Mpris.players ? Mpris.players.values : [];
        for (var i = 0; i < players.length; i++) if (players[i] && players[i].isPlaying) return players[i];
        for (var j = 0; j < players.length; j++) if (players[j] && (players[j].trackTitle || players[j].trackArtist)) return players[j];
        return null;
    }
    readonly property var player: media && media.activePlayer ? media.activePlayer : directPlayer
    readonly property bool mediaPlaying: !!(player && player.isPlaying)
    readonly property string reportedArt: player && player.trackArtUrl ? String(player.trackArtUrl) : ""
    readonly property string mediaTitle: player ? String(player.trackTitle || "") : ""
    property string keptArt: ""
    property string keptArtTitle: ""
    readonly property string mediaArt: reportedArt || (mediaTitle === keptArtTitle ? keptArt : "")
    property var audioLevels: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property bool audioActive: false
    readonly property bool mediaPill: view === "rest" && (mediaPlaying || audioActive) && islandSettings.mediaPill && !downloadPill
    property string askQuestion: ""
    readonly property var askProviders: ({
        "claude": {
            "name": "Claude",
            "cli": "claude",
            "glyph": "\uec82",
            "tile": "#d97757",
            "ink": "#ffffff"
        },
        "chatgpt": {
            "name": "Codex",
            "cli": "codex",
            "glyph": "\uec81",
            "tile": "#f2f2f2",
            "ink": "#000000"
        }
    })
    readonly property var askProvider: islandSettings.askAi === "none" ? null : askProviders[islandSettings.askAi] || askProviders.chatgpt
    readonly property Item downloadTracker: downloadWatcher
    readonly property Item packageTracker: packageWatcher
    readonly property bool downloadDone: view === "rest" && (downloadTracker.finishedName !== "" || packageTracker.finishedTitle !== "")
    readonly property bool downloadActive: view === "rest" && (downloadTracker.active || packageTracker.active) && !downloadDone
    readonly property bool downloadPill: downloadDone || downloadActive
    readonly property color mediaTint: {
        var best = null, bestScore = -1;
        var colors = coverColors.colors || [];
        for (var i = 0; i < colors.length; i++) {
            var c = colors[i];
            var score = c.hsvSaturation * 0.7 + c.hsvValue * 0.3;
            if (score > bestScore) {
                bestScore = score;
                best = c;
            }
        }
        if (!best || best.hsvSaturation < 0.12)
            return colorAccent;

        return Qt.hsva(best.hsvHue, Math.min(1, best.hsvSaturation), Math.max(0.75, best.hsvValue), 1);
    }
    readonly property real volume: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Pipewire.defaultAudioSink.audio.volume : -1
    readonly property bool muted: !!(Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted)
    property int brightnessState: -1
    readonly property var microphone: Pipewire.defaultAudioSource
    readonly property string keyboardLayoutLabel: {
        var entries = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets("omarchy.keyboard-layout") : [];
        return entries.length && entries[0].layoutLabel ? String(entries[0].layoutLabel) : "";
    }
    readonly property bool microphoneMuted: !!(microphone && microphone.audio && microphone.audio.muted)
    readonly property string wantedOutput: String(barConfig.output || "DP-1")
    readonly property string outputName: {
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) if (screens[i].name === wantedOutput) {
            return wantedOutput;
        }
        var focused = Hyprland.focusedMonitor;
        if (focused && focused.name)
            return String(focused.name);

        return screens.length ? String(screens[0].name) : "";
    }
    readonly property string home: Quickshell.env("HOME")
    property var settings: ({
    })
    readonly property QtObject islandSettings: settingsData
    readonly property var controlCenterKeys: {
        var known = ["wifi", "bluetooth", "focus", "game", "night", "weather", "sound", "display"];
        var saved = String(islandSettings.controlCenterOrder || "").split(",");
        var result = [];
        for (var i = 0; i < saved.length; i++) if (known.indexOf(saved[i]) !== -1 && result.indexOf(saved[i]) === -1) {
            result.push(saved[i]);
        }
        for (var j = 0; j < known.length; j++) if (result.indexOf(known[j]) === -1) {
            result.push(known[j]);
        }
        return result;
    }
    readonly property string feedPath: home + "/.local/state/omarchy/island-feed.json"
    readonly property string historyDir: home + "/.local/state/omarchy/notifications/history/"
    property string themeName: ""
    readonly property var clockDate: clock.date
    property string view: "rest"
    readonly property bool notificationPill: view === "feedback" && feedbackKind === "notification"
    readonly property bool volumePill: view === "feedback" && feedbackKind === "volume"
    readonly property bool brightnessPill: view === "feedback" && feedbackKind === "brightness"
    readonly property bool clipboardPill: view === "feedback" && feedbackKind === "clipboard"
    property var lastClip: null
    property string lastClipKey: ""
    property bool clipSeeded: false
    property double clipboardQuietUntil: 0
    property bool surfaceContentReady: false
    property string feedback: ""
    property string feedbackKind: ""
    property var activeNotifications: []
    property var lastNotification: null
    property var surfaceNames: []
    readonly property bool surfaceOpen: surfaceNames.indexOf(view) !== -1
    property var history: []
    property string lastNotificationKey: ""
    property bool initialized: false
    readonly property bool barHidden: barOffFlag.count > 0
    // its center section. The overlay is positioned from the clock widget, which
    // follows the existing center alignment regardless of surrounding widgets.
    readonly property int barSize: 26
    readonly property color barBackground: bar ? bar.background : Color.bar.background
    readonly property color barForeground: bar ? bar.barForeground : Color.bar.text
    readonly property string position: "top"
    // Follow Omarchy's live font alias so user font changes apply to the Island too.
    readonly property string fontFamily: Style.font.family
    readonly property string uiFontFamily: Style.font.family
    readonly property color colorBackground: barBackground
    readonly property bool themeTextIsLight: luminance(Color.foreground) > 0.5
    readonly property color colorText: bar ? barForeground : (themeTextIsLight ? Color.foreground : Color.background)
    readonly property color colorMuted: Qt.tint(colorBackground, withAlpha(colorText, 0.64))
    readonly property color colorAccent: Color.accent
    readonly property color colorAccentText: contrastOn(Color.accent)
    readonly property color colorUrgent: Color.urgent
    // Expanded menus need a solid surface so windows behind the island cannot
    // show through device names and action buttons.
    readonly property color colorSurface: Qt.tint(withAlpha(Color.background, 1), withAlpha(Color.foreground, 0.06))
    // Match the existing bar: its background fills the pill and its foreground
    // is the label ink.
    readonly property color islandColor: barBackground
    readonly property color islandText: barForeground
    readonly property real motionScale: islandSettings.motionScale > 0 ? islandSettings.motionScale : 1.5
    readonly property var notificationBrands: ({
        "claude": {
            "glyph": "\uec82",
            "tile": "#d97757",
            "ink": "#ffffff"
        },
        "codex": {
            "glyph": "\uec81",
            "tile": "#f2f2f2",
            "ink": "#000000"
        }
    })
    readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
    property string updateState: ""
    property bool updateAnnouncePending: false
    property string menuRoute: "root"
    property string menuInitialQuery: ""

    function updateAudioLevels(line) {
        var parts = String(line || "").trim().split(";");
        if (parts.length < audioLevels.length)
            return ;

        var next = [];
        var peak = 0;
        for (var i = 0; i < audioLevels.length; i++) {
            next.push(Math.max(0, Math.min(1, Number(parts[i]) / 8)));
            peak = Math.max(peak, next[i]);
        }
        audioLevels = next;
        if (peak > 0.1) {
            audioActive = true;
            audioSilenceTimer.restart();
        }
    }

    function ask(question) {
        question = String(question || "").trim();
        if (!question || !askProvider)
            return ;

        askQuestion = question;
        view = "answer";
    }

    function openDownloads() {
        if (!downloadTracker.active && downloadTracker.finishedName === "") {
            packageTracker.dismissFinished();
            return ;
        }
        var path = downloadDone ? downloadTracker.finishedPath : downloadTracker.folder;
        downloadTracker.dismissFinished();
        downloadOpener.command = ["sh", "-c", '[ -e "$1" ] && exec xdg-open "$1"; exec xdg-open "$(dirname "$1")"', "sh", path];
        downloadOpener.startDetached();
    }

    function toggleMicrophone() {
        if (microphone && microphone.audio)
            microphone.audio.muted = !microphone.audio.muted;

    }

    function cycleKeyboardLayout() {
        var entries = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets("omarchy.keyboard-layout") : [];
        if (entries.length && typeof entries[0].cycleLayout === "function")
            entries[0].cycleLayout();

    }

    function controlCenterTitle(key) {
        var names = {
            "wifi": "Wi-Fi / Ethernet",
            "bluetooth": "Bluetooth",
            "focus": "Focus",
            "game": "Game Mode",
            "night": "Night Shift",
            "weather": "Weather",
            "sound": "Sound",
            "display": "Display"
        };
        return names[key] || key;
    }

    function controlCenterIsShown(key) {
        return String(islandSettings.controlCenterHidden || "").split(",").indexOf(key) === -1;
    }

    function setControlCenterShown(key, shown) {
        var hidden = String(islandSettings.controlCenterHidden || "").split(",").filter(function(item) {
            return item !== "" && item !== key;
        });
        if (!shown)
            hidden.push(key);

        islandSettings.controlCenterHidden = hidden.join(",");
    }

    function isHtml(text) {
        return /^\s*<(img|meta|html|!doctype|body|div|span|p|a|picture|figure|table)\b/i.test(String(text || ""));
    }

    function clipboardChanged(raw) {
        var history = ClipboardHistory.parseHistory(raw);
        var top = history.length ? history[0] : null;
        if (top && top.type === "text" && isHtml(top.text) && history.length > 1 && history[1].type === "image")
            top = history[1];

        var key = top ? ClipboardHistory.entryKey(top) : "";
        var fresh = clipSeeded && key !== "" && key !== lastClipKey;
        lastClipKey = key;
        clipSeeded = true;
        if (!fresh || !islandSettings.clipboard || Date.now() < clipboardQuietUntil)
            return ;

        lastClip = top;
        showFeedback("", 2200, "clipboard");
    }

    function registerSurface(name) {
        if (surfaceNames.indexOf(name) === -1)
            surfaceNames = surfaceNames.concat([name]);

    }

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function luminance(x) {
        return 0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b;
    }

    function contrastOn(c) {
        var l = luminance(c);
        return Math.abs(l - luminance(colorBackground)) > Math.abs(l - luminance(colorText)) ? colorBackground : colorText;
    }

    function notificationIconSource(row, appIconOnly) {
        if (!row)
            return "";

        if (notificationAgent(row))
            return "";

        var value = String((appIconOnly ? "" : row.image) || row.appIcon || "");
        if (value === "")
            return "";

        if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
            return value;

        if (value.charAt(0) === "/")
            return "file://" + value;

        return Quickshell.iconPath(value, true);
    }

    function notificationAgent(row) {
        var summary = String(row.summary || "");
        if (summary === "Claude Code")
            return "claude";

        var fromTerminal = /ghostty|kitty|alacritty|foot|wezterm/i.test(String(row.appIcon || "") + " " + String(row.app || ""));
        if (summary === "Codex" || (fromTerminal && /^(Ghostty|kitty|Alacritty|foot|WezTerm)$/.test(summary)))
            return "codex";

        return "";
    }

    function notificationBrand(row) {
        var agent = row ? notificationAgent(row) : "";
        return agent ? notificationBrands[agent] : null;
    }

    function notificationTitle(row) {
        if (!row)
            return "Notification";

        if (notificationAgent(row) === "codex")
            return "Codex";

        return String(row.summary || row.app || "Notification");
    }

    function notificationAge(timestamp) {
        var ms = Date.now() - Number(timestamp || 0);
        if (!timestamp || ms < 60000)
            return "now";

        if (ms < 3.6e+06)
            return Math.floor(ms / 60000) + "m ago";

        if (ms < 8.64e+07)
            return Math.floor(ms / 3.6e+06) + "h ago";

        return Qt.formatDateTime(new Date(Number(timestamp)), "d MMM");
    }

    function surfaceOpenFor(v) {
        return surfaceNames.indexOf(v) !== -1;
    }

    function showFeedback(message, duration, kind) {
        if (surfaceOpen)
            return ;

        if (feedbackKind === "notification" && kind !== "notification" && feedbackTimer.running)
            return ;

        feedback = String(message || "");
        feedbackKind = String(kind || "system");
        view = "feedback";
        feedbackTimer.interval = duration || 2800;
        feedbackTimer.restart();
    }

    function updateRow(body) {
        return {
            "summary": "Island Update",
            "body": body,
            "glyph": "󰚰",
            "timestamp": Date.now(),
            "islandUpdate": true
        };
    }

    function announceUpdate() {
        if (surfaceOpen || view === "feedback") {
            updateAnnouncePending = true;
            return ;
        }
        updateAnnouncePending = false;
        lastNotification = updateRow("A new version is ready. Click to update.");
        showFeedback("", 10000, "notification");
    }

    function updateIsland() {
        if (updateState === "updating")
            return ;

        updateState = "updating";
        lastNotification = updateRow("Updating Island…");
        showFeedback("", 120000, "notification");
        islandUpdate.running = true;
    }

    function loadFeed(raw) {
        try {
            var parsed = JSON.parse(raw || "{}");
            var rows = Array.isArray(parsed.active) ? parsed.active : [];
            activeNotifications = rows;
            if (view === "controls")
                refreshHistory();

            if (!rows.length)
                return ;

            var current = rows[0];
            var key = String(current.timestamp) + ":" + String(current.originalId);
            if (key === lastNotificationKey)
                return ;

            lastNotificationKey = key;
            lastNotification = current;
            if (!surfaceOpen)
                showFeedback(String(current.summary || current.app || "Notification"), islandSettings.bannerSeconds * 1000, "notification");

        } catch (e) {
            console.warn("island: notification feed parse failed", e);
        }
    }

    function refreshHistory() {
        if (historyProc.running)
            return ;

        historyProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", historyDir];
        historyProc.running = true;
    }

    function loadHistory(raw) {
        var rows = [];
        for (var j = 0; j < activeNotifications.length; j++) {
            var active = Object.assign({
            }, activeNotifications[j]);
            active.isActive = true;
            rows.push(active);
        }
        var lines = String(raw || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            if (!lines[i].trim())
                continue;

            try {
                rows.push(JSON.parse(lines[i]));
            } catch (e) {
            }
        }
        rows.sort(function(a, b) {
            return Number(b.timestamp || 0) - Number(a.timestamp || 0);
        });
        history = rows.slice(0, 10);
    }

    function notificationKey(row) {
        return String(row.timestamp) + ":" + String(row.originalId);
    }

    function notificationCommand(method, row) {
        notificationProc.command = ["omarchy-shell", "notifications", method, notificationKey(row)];
        notificationProc.running = true;
    }

    function dismissPillNotification() {
        var row = lastNotification;
        feedbackKind = "";
        view = "rest";
        if (row)
            notificationCommand("dismissKey", row);

    }

    function clearAllNotifications() {
        history = [];
        notificationProc.command = ["bash", "-c", "omarchy-shell notifications dismissAll; omarchy-shell notifications clear"];
        notificationProc.running = true;
    }

    function dismissNotification(row) {
        var key = notificationKey(row);
        history = history.filter(function(r) {
            return notificationKey(r) !== key;
        });
        if (row.isActive) {
            notificationProc.command = ["omarchy-shell", "notifications", "dismissKey", key];
        } else {
            var stem = String(row.timestamp) + "-" + String(row.originalId);
            notificationProc.command = ["bash", "-c", "rm -f \"$1/$2.json\" \"$1/../images/$2\"-*", "--", historyDir, stem];
        }
        notificationProc.running = true;
    }

    function toggleView(name) {
        view = view === name ? "rest" : name;
        return view;
    }

    // A zero-sized widget slot can suppress layout anchoring even though the
    // full-screen layer window exists. Keep a real, bar-height center anchor.
    implicitWidth: 1
    implicitHeight: 26
    visible: true
    onReportedArtChanged: {
        if (reportedArt) {
            keptArt = reportedArt;
            keptArtTitle = mediaTitle;
        }
    }
    onMediaTitleChanged: {
        if (mediaTitle !== keptArtTitle) {
            keptArt = reportedArt;
            keptArtTitle = mediaTitle;
        }
    }
    onViewChanged: {
        if (view === "rest" && updateAnnouncePending)
            Qt.callLater(announceUpdate);

        surfaceContentReady = false;
        if (surfaceOpenFor(view))
            surfaceRevealTimer.restart();
        else
            surfaceRevealTimer.stop();
        if (view === "controls")
            refreshHistory();

    }
    onVolumeChanged: {
        if (initialized && volume >= 0 && islandSettings.volumeHud)
            showFeedback("", 1800, "volume");

    }
    onMutedChanged: {
        if (initialized && volume >= 0 && islandSettings.volumeHud)
            showFeedback("", 1800, "volume");

    }
    onBrightnessStateChanged: {
        if (initialized && brightnessState >= 0 && islandSettings.volumeHud)
            showFeedback("", 1800, "brightness");
    }
    Component.onCompleted: {
        initialized = true;
    }

    Process {
        id: audioCapture

        command: ["cava", "-p", Qt.resolvedUrl("components/cava.conf").toString().replace("file://", "")]
        running: root.islandSettings.mediaPill

        stdout: SplitParser {
            onRead: function(line) {
                root.updateAudioLevels(line);
            }
        }

    }

    Process {
        id: brightnessStateProbe
        command: ["omarchy-monitor-state"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var value = Number(String(text || "").trim().split(/\\s+/)[0]);
                if (Number.isFinite(value)) root.brightnessState = Math.max(0, Math.min(100, Math.round(value)));
            }
        }
    }

    Timer {
        interval: 350
        repeat: true
        running: root.initialized
        onTriggered: if (!brightnessStateProbe.running) brightnessStateProbe.running = true
    }

    Timer {
        id: audioSilenceTimer

        interval: 1800
        onTriggered: root.audioActive = false
    }

    Downloads {
        id: downloadWatcher

        enabled: root.islandSettings.downloads
    }

    PackageUpdates {
        id: packageWatcher

        enabled: root.islandSettings.systemUpdates
    }

    Process {
        id: downloadOpener
    }

    ColorQuantizer {
        id: coverColors

        source: root.mediaArt
        depth: 2
        rescaleSize: 64
    }

    FileView {
        path: root.home + "/.config/omarchy/island.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: function(error) {
            if (error !== FileViewError.FileNotFound)
                return ;

            writeAdapter();
            Qt.callLater(reload);
        }

        JsonAdapter {
            id: settingsData

            property real motionScale: 1.5
            property bool hoverLift: true
            property bool clock24h: true
            property bool mediaPill: true
            property bool volumeHud: true
            property int bannerSeconds: 5
            property bool notch: false
            property bool downloads: true
            property bool clipboard: true
            property bool systemUpdates: true
            property bool colorfulSettingsIcons: true
            property string controlCenterOrder: "wifi,bluetooth,weather,focus,night,sound,display"
            property string controlCenterHidden: "game"
            property string askAi: "chatgpt"
        }

    }

    FileView {
        path: root.home + "/.local/state/omarchy/clipboard-history.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.clipboardChanged(text())
    }

    FolderListModel {
        id: barOffFlag

        folder: "file://" + root.home + "/.local/state/omarchy/toggles"
        nameFilters: ["bar-off"]
        showDirs: false
        showHidden: true
    }
    // Keep the host bar's normal top reservation while the Island floats above

    FileView {
        path: root.home + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        printErrors: false
        onLoaded: root.themeName = text().trim()
        onFileChanged: reload()
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: {
            interval = 6 * 3600 * 1000;
            if (!updateCheck.running && root.updateState !== "updating")
                updateCheck.running = true;

        }
    }

    Process {
        id: updateCheck

        command: ["bash", "-c", "cd \"$1\" && [ -d .git ] || exit 0; export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -oBatchMode=yes'; remote=$(timeout 30 git ls-remote origin HEAD 2>/dev/null | cut -f1); [ -n \"$remote\" ] || exit 0; git merge-base --is-ancestor \"$remote\" HEAD 2>/dev/null || echo available", "update-check", root.pluginDir]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (String(text || "").trim() !== "available" || root.updateState === "updating")
                    return ;

                root.updateState = "available";
                root.announceUpdate();
            }
        }

    }

    Process {
        id: islandUpdate

        command: ["setsid", "-f", "bash", "-c", "if omarchy-plugin-update \"$1\" --yes >/dev/null 2>&1; then omarchy restart shell; else notify-send -a Island -i system-software-update 'Island Update' \"Couldn't update. The plugin folder has local changes.\"; fi", "island-update", root.pluginDir.replace(/.*\//, "")]
    }

    Timer {
        id: feedbackTimer

        repeat: false
        onTriggered: {
            if (root.view === "feedback")
                root.view = "rest";

            root.feedbackKind = "";
        }
    }

    Timer {
        id: surfaceRevealTimer

        interval: 90 * root.motionScale
        repeat: false
        onTriggered: root.surfaceContentReady = true
    }

    FileView {
        id: feedFile

        path: root.feedPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadFeed(text())
        onFileChanged: reload()
    }

    Process {
        id: historyProc

        running: false

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.loadHistory(text)
        }

    }

    Process {
        id: notificationProc

        running: false
        onExited: root.refreshHistory()
    }

    IpcHandler {
        function show(name: string) : string {
            if (name === "menu")
                root.menuRoute = "root";

            return root.toggleView(name);
        }

        function openMenu(route: string) : string {
            root.menuRoute = String(route || "root");
            root.view = "menu";
            return root.view;
        }

        function toggle() : string {
            return root.toggleView("controls");
        }

        function themes() : string {
            return root.toggleView("themes");
        }

        function wallpapers() : string {
            return root.toggleView("wallpapers");
        }

        function apps() : string {
            return root.toggleView("apps");
        }

        function power() : string {
            return root.toggleView("power");
        }

        function ask(question: string) : string {
            root.ask(question);
            return root.view;
        }

        function showHistory() : string {
            root.view = "controls";
            return root.view;
        }

        function close() : string {
            root.view = "rest";
            return "rest";
        }

        target: "guilhermerisu.island"
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: window

                required property var modelData

                screen: modelData
                visible: modelData.name === root.outputName
                color: "transparent"
                surfaceFormat.opaque: false
                exclusionMode: ExclusionMode.Ignore
                implicitHeight: 800
                WlrLayershell.namespace: "omarchy-island"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: island.activeSurface && island.activeSurface.wantsKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                anchors {
                    top: true
                    left: true
                    right: true
                }

                // Expanded views accept an outside click to close. A full-screen
                // dimmer would feel unlike the rest of the bar, so keep the desktop
                // visible and make only this transparent input layer active.
                MouseArea {
                    id: outsideClick

                    anchors.fill: parent
                    visible: root.surfaceOpen
                    enabled: root.surfaceOpen
                    z: 1
                    onClicked: function(mouse) {
                        if (island.contains(island.mapFromItem(outsideClick, mouse.x, mouse.y)))
                            return ;

                        root.view = "rest";
                    }
                }

                HyprlandFocusGrab {
                    id: focusGrab

                    property bool armed: false

                    windows: [window]
                    active: window.visible && root.surfaceOpen && armed
                    onCleared: {
                        if (root.surfaceOpen)
                            root.view = "rest";

                    }
                }

                Timer {
                    interval: 120
                    running: root.surfaceOpen
                    onTriggered: focusGrab.armed = true
                }

                Connections {
                    function onSurfaceOpenChanged() {
                        if (!root.surfaceOpen)
                            focusGrab.armed = false;

                    }

                    target: root
                }

                Canvas {
                    id: leftEar

                    readonly property real r: 10

                    visible: root.islandSettings.notch
                    x: island.x - r
                    y: island.y
                    width: r
                    height: r
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.fillStyle = root.colorBackground;
                        ctx.beginPath();
                        ctx.moveTo(r, 0);
                        ctx.lineTo(r, r);
                        ctx.arc(0, r, r, 0, -Math.PI / 2, true);
                        ctx.closePath();
                        ctx.fill();
                    }
                }

                Canvas {
                    id: rightEar

                    readonly property real r: 10

                    visible: root.islandSettings.notch
                    x: island.x + island.width
                    y: island.y
                    width: r
                    height: r
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.fillStyle = root.colorBackground;
                        ctx.beginPath();
                        ctx.moveTo(0, 0);
                        ctx.lineTo(0, r);
                        ctx.arc(r, r, r, Math.PI, 1.5 * Math.PI, false);
                        ctx.closePath();
                        ctx.fill();
                    }
                }

                Rectangle {
                    id: island

                    readonly property Item activeSurface: views.surfaceFor(root.view)
                    readonly property real targetWidth: activeSurface ? activeSurface.islandWidth : root.notificationPill ? 440 : root.volumePill || root.brightnessPill ? 240 : root.clipboardPill ? 320 : root.view === "feedback" ? 280 : root.downloadDone ? 360 : root.downloadActive ? (root.downloadTracker.active ? 240 : 280) : root.mediaPill ? 320 : 100
                    readonly property real targetHeight: activeSurface ? activeSurface.islandHeight : root.notificationPill ? 84 : root.clipboardPill ? (root.islandSettings.notch ? 40 : 44) : root.downloadDone ? 64 : root.mediaPill ? (root.islandSettings.notch ? 50 : 54) : root.downloadPill ? (root.islandSettings.notch ? 40 : 44) : root.volumePill || root.brightnessPill ? 56 : root.view === "rest" ? 28 : 42
                    property real radiusCap: root.volumePill || root.brightnessPill ? 20 : root.view === "answer" ? 44 : root.surfaceOpen ? 30 : 38
                    readonly property real springStiffness: 6.5 / root.motionScale
                    property real springWidth: targetWidth
                    property real springHeight: targetHeight

                    z: 2
                    x: (parent.width - width) / 2
                    // Center the pill within the reserved bar row. The prior fixed
                    // negative offset clipped the capsule at the top of the display.
                    // Inset the capsule between the screen edge and the window row.
                    // At rest this leaves roughly 6 px above and below the pill.
                    y: root.barHidden && root.view === "rest" ? -height - 12 : 6
                    radius: Math.min(height / 2, root.islandSettings.notch && !root.surfaceOpen ? Math.min(radiusCap, 16) : radiusCap)
                    topLeftRadius: radius
                    topRightRadius: radius
                    scale: root.view === "rest" && clockHover.hovered && root.islandSettings.hoverLift && !root.islandSettings.notch ? 1.07 : 1
                    color: root.surfaceOpen ? root.colorSurface : root.islandColor
                    border.width: root.surfaceOpen ? 1 : 0
                    border.color: root.withAlpha(root.colorAccent, 0.3)
                    clip: true
                    width: Math.max(40, springWidth)
                    height: Math.max(28, springHeight)

                    HoverHandler {
                        id: clockHover

                        enabled: root.view === "rest"
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.view === "rest" || root.view === "feedback"
                        onClicked: function(mouse) {
                            feedbackTimer.stop();
                            if (root.notificationPill && root.lastNotification && root.lastNotification.islandUpdate)
                                root.updateIsland();
                            else if (root.notificationPill)
                                root.dismissPillNotification();
                            else if (root.clipboardPill)
                                root.view = "clipboard";
                            else if (root.downloadDone || (root.downloadActive && (mouse.x < 56 || mouse.x > width - 90)))
                                root.openDownloads();
                            else if (root.mediaPill && (mouse.x < 56 || mouse.x > width - 72))
                                root.view = root.mediaPlaying ? "player" : "controls";
                            else
                                root.view = "controls";
                        }
                    }

                    NotificationPill {
                        host: root
                        shape: island
                        anchors.fill: parent
                    }

                    VolumeSlider {
                        host: root
                        shape: island
                        anchors.fill: parent
                    }

                    ClipboardPill {
                        host: root
                        anchors.fill: parent
                    }

                    MediaPill {
                        host: root
                        anchors.fill: parent
                    }

                    DownloadPill {
                        host: root
                        anchors.fill: parent
                    }

                    IslandLabel {
                        host: root
                        anchors.centerIn: parent
                    }

                    Views {
                        id: views

                        host: root
                        anchors.fill: parent
                    }

                    Behavior on y {
                        NumberAnimation {
                            duration: 300 * root.motionScale
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on radiusCap {
                        NumberAnimation {
                            duration: 390 * root.motionScale
                            easing.type: Easing.OutQuint
                        }

                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 240 * root.motionScale
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.8
                        }

                    }

                    Behavior on springWidth {
                        SpringAnimation {
                            spring: island.springStiffness
                            damping: 0.4
                            mass: 1
                            epsilon: 0.2
                        }

                    }

                    Behavior on springHeight {
                        SpringAnimation {
                            spring: island.springStiffness
                            damping: 0.4
                            mass: 1
                            epsilon: 0.2
                        }

                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 240 * root.motionScale
                            easing.type: Easing.InOutQuad
                        }

                    }

                }

                mask: Region {
                    item: root.surfaceOpen ? outsideClick : island
                }

            }

        }

    }

}
