import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import "file:///usr/share/omarchy/shell/plugins/panels/bluetooth/Model.js" as BluetoothModel
import "file:///usr/share/omarchy/shell/plugins/panels/network/Model.js" as NetworkModel

import qs.Commons
// In-pill versions of Omarchy's Network and Bluetooth menus. The actions use
// the same NetworkManager and BlueZ services as the stock bar panels.
ColumnLayout {
    id: page

    required property var host
    property string mode: "network"
    property bool active: false
    property string passwordSsid: ""
    property string password: ""
    property string identity: ""
    property string pendingWifiSsid: ""
    property string notice: ""
    property string dnsCurrent: "DHCP"
    property string bandCurrent: ""
    property string bandSelected: "auto"
    property var bands: []
    property var pendingActions: ({
    })
    property bool scannerWasEnabled: false
    property bool discoveryOwned: false
    readonly property bool isNetwork: mode === "network"
    readonly property color textColor: host.colorText
    readonly property color mutedColor: host.colorMuted
    readonly property color accent: host.colorAccent
    readonly property color accentText: host.colorAccentText
    readonly property color panelColor: host.colorSurface
    readonly property color cardColor: Qt.tint(panelColor, host.withAlpha(textColor, 0.075))
    readonly property color hoverColor: Qt.tint(panelColor, host.withAlpha(textColor, 0.15))
    readonly property color edgeColor: host.withAlpha(textColor, 0.11)
    readonly property string iconFont: host.fontFamily
    readonly property var devices: Networking.devices ? Networking.devices.values : []
    readonly property var wifiDevice: findDevice(DeviceType.Wifi)
    readonly property var wiredDevice: findDevice(DeviceType.Wired)
    readonly property var wifiNetworks: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    readonly property var wifiRows: {
        var rows = [];
        for (var i = 0; i < wifiNetworks.length; i++) {
            var row = NetworkModel.wifiRow(wifiNetworks[i]);
            if (row)
                rows.push(row);

        }
        return NetworkModel.sortWifiRows(rows);
    }
    readonly property var connectedNetwork: {
        for (var i = 0; i < wifiNetworks.length; i++) if (wifiNetworks[i] && wifiNetworks[i].connected) {
            return wifiNetworks[i];
        }
        return null;
    }
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var bluetoothDevices: Bluetooth.devices ? Bluetooth.devices.values : []
    readonly property var btGroups: BluetoothModel.deviceLists(bluetoothDevices)
    readonly property var connectedBt: btGroups.connected.map(BluetoothModel.deviceRow)
    readonly property var pairedBt: btGroups.known.map(BluetoothModel.deviceRow)
    readonly property var availableBt: btGroups.discovered.map(BluetoothModel.deviceRow)

    function bluetoothLabel(device) {
        return BluetoothModel.deviceLabel(device);
    }

    function findDevice(type) {
        var fallback = null;
        for (var i = 0; i < devices.length; i++) {
            var d = devices[i];
            if (!d || d.type !== type)
                continue;

            if (d.connected)
                return d;

            if (!fallback)
                fallback = d;

        }
        return fallback;
    }

    function wifiNeedsPassword(net) {
        return !!net && net.security !== WifiSecurityType.Open && net.security !== WifiSecurityType.Owe;
    }

    function wifiEnterprise(net) {
        return !!net && (net.security === WifiSecurityType.Wpa2Eap || net.security === WifiSecurityType.WpaEap);
    }

    function networkForSsid(ssid) {
        for (var i = 0; i < wifiNetworks.length; i++) if (wifiNetworks[i] && wifiNetworks[i].name === ssid) {
            return wifiNetworks[i];
        }
        return null;
    }

    function connectWifiRow(row) {
        var net = networkForSsid(row ? row.ssid : "");
        if (!net || net.stateChanging)
            return ;

        notice = "";
        if (net.connected) {
            net.disconnect();
            return ;
        }
        if (wifiNeedsPassword(net) && !net.known) {
            passwordSsid = net.name || "";
            password = "";
            identity = "";
            return ;
        }
        pendingWifiSsid = net.name || "";
        net.connect();
    }

    function submitPassword() {
        var net = networkForSsid(passwordSsid);
        if (!net || password.length === 0)
            return ;

        pendingWifiSsid = passwordSsid;
        if (wifiEnterprise(net)) {
            if (identity.trim() === "") {
                notice = "Enter your network identity.";
                return ;
            }
            enterpriseConnect.secret = password;
            enterpriseConnect.command = ["bash", "-c", NetworkModel.enterpriseConnectScript, "nmcli-eap", passwordSsid, identity];
            enterpriseConnect.running = true;
        } else {
            net.connectWithPsk(password);
        }
        password = "";
        identity = "";
        passwordSsid = "";
    }

    function forgetWifi(net) {
        if (net && net.known && !net.connected)
            net.forget();

    }

    function scanWifi() {
        if (!wifiDevice)
            return ;

        wifiDevice.scannerEnabled = false;
        wifiScanDelay.restart();
    }

    function runCommand(command) {
        if (commandProc.running)
            return ;

        commandProc.command = command;
        commandProc.running = true;
    }

    function setDns(provider) {
        if (provider === "Custom") {
            Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-dns Custom"]);
            return ;
        }
        runCommand(["omarchy-dns", provider]);
        dnsCurrent = provider;
    }

    function setBand(band) {
        bandSelected = band;
        runCommand(["omarchy-network-band", band]);
    }

    function bluetoothAction(device, action) {
        if (!device || !device.address)
            return ;

        var liveDevice = bluetoothDeviceFor(device.address);
        if (!liveDevice)
            return ;

        var next = ({
        });
        for (var key in pendingActions) next[key] = pendingActions[key]
        next[device.address] = action === "pair" ? "pairing" : action + "ing";
        pendingActions = next;
        if (action === "disconnect") {
            if (liveDevice.disconnect)
                liveDevice.disconnect();

            Quickshell.execDetached(["omarchy-bluetooth-device", action, device.address]);
        } else {
            Quickshell.execDetached(["omarchy-bluetooth-device", action, device.address]);
        }
        actionTimeout.restart();
    }

    function bluetoothDeviceFor(address) {
        for (var i = 0; i < bluetoothDevices.length; i++) if (bluetoothDevices[i] && bluetoothDevices[i].address === address) {
            return bluetoothDevices[i];
        }
        return null;
    }

    function toggleBluetooth() {
        if (adapter)
            Quickshell.execDetached(["omarchy-bluetooth-power", adapter.enabled ? "off" : "on"]);

    }

    onActiveChanged: {
        if (isNetwork) {
            if (active && wifiDevice) {
                scannerWasEnabled = wifiDevice.scannerEnabled;
                wifiDevice.scannerEnabled = true;
                bandProc.running = true;
                dnsProc.running = true;
            } else if (!active && wifiDevice) {
                wifiDevice.scannerEnabled = scannerWasEnabled;
                passwordSsid = "";
                password = "";
            }
        } else if (adapter) {
            if (active) {
                discoveryOwned = !adapter.discovering;
                if (discoveryOwned && adapter.enabled)
                    adapter.discovering = true;

            } else if (discoveryOwned && adapter.discovering) {
                adapter.discovering = false;
                discoveryOwned = false;
            }
        }
    }
    spacing: 12

    Timer {
        id: wifiScanDelay

        interval: 350
        onTriggered: {
            if (page.active && page.wifiDevice)
                page.wifiDevice.scannerEnabled = true;

        }
    }

    Timer {
        id: actionTimeout

        interval: 20000
        onTriggered: page.pendingActions = ({
        })
    }

    Timer {
        interval: 1000
        repeat: true
        running: page.active && !page.isNetwork && !!page.adapter && page.adapter.enabled && !page.adapter.discovering
        onTriggered: {
            page.discoveryOwned = true;
            page.adapter.discovering = true;
        }
    }

    Connections {
        function onDiscoveringChanged() {
            if (page.active && page.adapter && page.adapter.discovering)
                page.discoveryOwned = true;

        }

        target: page.adapter
    }

    Process {
        id: commandProc

        onExited: {
            if (exitCode !== 0)
                page.notice = "That change could not be applied.";

        }
    }

    Process {
        id: enterpriseConnect

        property string secret: ""

        stdinEnabled: true
        onStarted: {
            write(secret + "\n");
            secret = "";
        }
        onExited: {
            if (exitCode !== 0)
                page.notice = "Could not connect. Check the identity and password.";

        }
    }

    Timer {
        interval: 500
        repeat: true
        running: page.active && !page.isNetwork
        onTriggered: {
            var next = ({
            });
            var changed = false;
            for (var address in page.pendingActions) {
                var action = page.pendingActions[address];
                var device = page.bluetoothDeviceFor(address);
                var done = action === "connecting" && device && device.connected || action === "pairing" && device && device.paired && device.connected || action === "disconnecting" && device && !device.connected || action === "forgetting" && (!device || (!device.paired && !device.bonded && !device.trusted));
                if (done)
                    changed = true;
                else
                    next[address] = action;
            }
            if (changed)
                page.pendingActions = next;

        }
    }

    Process {
        id: dnsProc

        command: ["omarchy-dns"]

        stdout: StdioCollector {
            onStreamFinished: {
                var v = String(text || "").trim();
                if (v)
                    page.dnsCurrent = v;

            }
        }

    }

    Process {
        id: bandProc

        command: ["omarchy-network-band"]

        stdout: StdioCollector {
            onStreamFinished: {
                var raw = String(text || "");
                var available = raw.match(/^available\t(.*)$/m);
                var current = raw.match(/^band\t([^\n]+)/m);
                var selected = raw.match(/^selected\t([^\n]+)/m);
                page.bands = available && available[1] ? available[1].trim().split(/\s+/) : [];
                page.bandCurrent = current ? current[1] : "";
                page.bandSelected = selected ? selected[1] : "auto";
            }
        }

    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 42
            Layout.preferredHeight: 42
            radius: 14
            color: host.withAlpha(accent, 0.19)
            border.width: 1
            border.color: host.withAlpha(accent, 0.32)

            Text {
                anchors.centerIn: parent
                text: page.isNetwork ? "󰖩" : "󰂯"
                color: accent
                font.family: iconFont
                font.pixelSize: 21
            }

        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                text: page.isNetwork ? "Network" : "Bluetooth"
                color: textColor
                font.family: Style.font.family
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: page.isNetwork ? (connectedNetwork ? connectedNetwork.name : wiredDevice && wiredDevice.connected ? "Ethernet connected" : "Not connected") : (!adapter ? "No Bluetooth adapter" : !adapter.enabled ? "Bluetooth is off" : connectedBt.length ? connectedBt.length + " device" + (connectedBt.length === 1 ? "" : "s") + " connected" : "Ready to pair")
                color: mutedColor
                font.family: Style.font.family
                font.pixelSize: 11
            }

        }

        MenuButton {
            theme: page
            label: "‹"
            hint: "Back to controls"
            onClicked: host.view = "controls"
        }

        MenuButton {
            theme: page
            label: "×"
            hint: "Close"
            onClicked: host.view = "rest"
        }

    }

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: edgeColor
    }

    ColumnLayout {
        visible: page.isNetwork
        Layout.fillWidth: true
        spacing: 9

        RowLayout {
            Layout.fillWidth: true

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                radius: 12
                color: Networking.wifiEnabled ? host.withAlpha(accent, 0.18) : cardColor
                border.width: 1
                border.color: Networking.wifiEnabled ? host.withAlpha(accent, 0.35) : edgeColor

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8

                    Text {
                        text: "Wi-Fi"
                        color: textColor
                        font.family: Style.font.family
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }

                    Text {
                        text: Networking.wifiEnabled ? "On" : "Off"
                        color: mutedColor
                        font.family: Style.font.family
                        font.pixelSize: 11
                    }

                    MenuButton {
                        theme: page
                        label: "Toggle"
                        active: Networking.wifiEnabled
                        onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                    }

                }

            }

            MenuButton {
                theme: page
                label: "↻ Scan"
                enabled: !!wifiDevice
                onClicked: scanWifi()
            }

        }

        Text {
            visible: !wifiDevice
            text: "No Wi-Fi adapter found"
            color: mutedColor
            font.family: Style.font.family
            font.pixelSize: 12
        }

        Text {
            visible: !!wiredDevice && wiredDevice.connected
            text: "Ethernet is connected"
            color: mutedColor
            font.family: Style.font.family
            font.pixelSize: 11
        }

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Nearby networks"
                color: textColor
                font.family: Style.font.family
                font.pixelSize: 12
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }

            Text {
                text: wifiDevice && wifiDevice.scannerEnabled ? "Scanning" : ""
                color: accent
                font.family: Style.font.family
                font.pixelSize: 10
            }

        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(wifiList.contentHeight + 8, 208)
            implicitHeight: 1
            radius: 14
            color: cardColor
            border.width: 1
            border.color: edgeColor

            ListView {
                id: wifiList

                anchors.fill: parent
                anchors.margins: 4
                clip: true
                spacing: 2
                model: page.wifiRows

                Text {
                    anchors.centerIn: parent
                    visible: wifiList.count === 0
                    text: wifiDevice && Networking.wifiEnabled ? "Looking for networks…" : "Turn on Wi-Fi to scan"
                    color: mutedColor
                    font.family: Style.font.family
                    font.pixelSize: 11
                }

                delegate: Rectangle {
                    required property var modelData

                    width: wifiList.width
                    height: 44
                    radius: 10
                    color: modelData.connected ? host.withAlpha(accent, 0.1) : rowMouse.containsMouse ? hoverColor : "transparent"

                    Connections {
                        function onConnectionFailed() {
                            if (page.pendingWifiSsid !== modelData.ssid)
                                return ;

                            page.pendingWifiSsid = "";
                            var failedNetwork = page.networkForSsid(modelData.ssid);
                            if (page.wifiNeedsPassword(failedNetwork)) {
                                page.passwordSsid = modelData.ssid;
                                page.password = "";
                                page.identity = "";
                            } else {
                                page.notice = "Could not connect to " + modelData.ssid + ".";
                            }
                        }

                        function onConnectedChanged() {
                            var current = page.networkForSsid(modelData.ssid);
                            if (page.pendingWifiSsid === modelData.ssid && current && current.connected)
                                page.pendingWifiSsid = "";

                        }

                        target: page.networkForSsid(modelData.ssid)
                    }

                    MouseArea {
                        id: rowMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        onClicked: page.connectWifiRow(modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: modelData.connected ? "󰤨" : page.wifiNeedsPassword(modelData) ? "󰌾" : "󰤯"
                            color: modelData.connected ? accent : mutedColor
                            font.family: iconFont
                            font.pixelSize: 15
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: modelData.ssid || "Hidden network"
                                color: textColor
                                font.family: Style.font.family
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: modelData.connected ? "Connected" : modelData.known ? "Saved" : "Signal " + modelData.signal + "%"
                                color: modelData.connected ? accent : mutedColor
                                font.family: Style.font.family
                                font.pixelSize: 10
                            }

                        }

                        MenuButton {
                            theme: page
                            visible: !!modelData.known && !modelData.connected
                            label: "Forget"
                            onClicked: page.forgetWifi(page.networkForSsid(modelData.ssid))
                        }

                        Text {
                            visible: !!page.networkForSsid(modelData.ssid) && page.networkForSsid(modelData.ssid).stateChanging
                            text: "…"
                            color: accent
                            font.pixelSize: 16
                        }

                    }

                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

            }

        }

        RowLayout {
            visible: page.passwordSsid !== ""
            Layout.fillWidth: true

            TextField {
                id: passwordInput

                Layout.fillWidth: true
                placeholderText: "Password for " + page.passwordSsid
                echoMode: TextInput.Password
                color: textColor
                selectionColor: host.withAlpha(accent, 0.45)
                onTextChanged: page.password = text
                Keys.onReturnPressed: page.submitPassword()

                background: Rectangle {
                    radius: 10
                    color: cardColor
                    border.width: 1
                    border.color: edgeColor
                }

            }

            MenuButton {
                theme: page
                label: "Connect"
                active: true
                enabled: page.password.length > 0
                onClicked: page.submitPassword()
            }

            MenuButton {
                theme: page
                label: "Cancel"
                onClicked: {
                    page.passwordSsid = "";
                    page.password = "";
                    page.identity = "";
                }
            }

        }

        RowLayout {
            visible: page.passwordSsid !== "" && page.wifiEnterprise(page.networkForSsid(page.passwordSsid))
            Layout.fillWidth: true

            TextField {
                Layout.fillWidth: true
                placeholderText: "Network identity"
                text: page.identity
                color: textColor
                onTextChanged: page.identity = text
                Keys.onReturnPressed: page.submitPassword()

                background: Rectangle {
                    radius: 10
                    color: cardColor
                    border.width: 1
                    border.color: edgeColor
                }

            }

        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            Text {
                text: "DNS"
                color: mutedColor
                font.family: Style.font.family
                font.pixelSize: 10
                Layout.rightMargin: 2
            }

            Repeater {
                model: ["DHCP", "Cloudflare", "Google", "Custom"]

                delegate: MenuButton {
                    required property string modelData

                    theme: page
                    label: modelData
                    active: page.dnsCurrent.toLowerCase().indexOf(modelData.toLowerCase()) >= 0
                    onClicked: page.setDns(modelData)
                }

            }

        }

        RowLayout {
            visible: page.bands.length > 1 || page.bandSelected !== "auto"
            Layout.fillWidth: true
            spacing: 5

            Text {
                text: "Band"
                color: mutedColor
                font.family: Style.font.family
                font.pixelSize: 10
                Layout.rightMargin: 2
            }

            MenuButton {
                theme: page
                label: "Auto"
                active: page.bandSelected === "auto"
                onClicked: page.setBand("auto")
            }

            Repeater {
                model: page.bands

                delegate: MenuButton {
                    required property string modelData

                    theme: page
                    label: modelData + " GHz"
                    active: page.bandSelected === modelData
                    onClicked: page.setBand(modelData)
                }

            }

        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            MenuButton {
                theme: page
                label: "Sign-in page"
                visible: !!connectedNetwork
                onClicked: Quickshell.execDetached(["omarchy-launch-browser", "http://ping.archlinux.org/nm-check.txt"])
            }

            MenuButton {
                theme: page
                label: "Share Wi-Fi"
                visible: !!connectedNetwork
                onClicked: {
                    host.view = "rest";
                    Qt.callLater(function() {
                        if (host.shell)
                            host.shell.summon("omarchy.wifiqr", JSON.stringify({
                            "ssid": connectedNetwork.name
                        }));

                    });
                }
            }

            MenuButton {
                theme: page
                label: "Speed test"
                visible: !!(connectedNetwork || (wiredDevice && wiredDevice.connected))
                onClicked: {
                    host.view = "rest";
                    Qt.callLater(function() {
                        if (host.shell)
                            host.shell.summon("omarchy.speedtest", "{}");

                    });
                }
            }

        }

    }

    ColumnLayout {
        visible: !page.isNetwork
        Layout.fillWidth: true
        Layout.preferredWidth: page.width
        spacing: 9

        RowLayout {
            Layout.fillWidth: true

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                radius: 12
                color: adapter && adapter.enabled ? host.withAlpha(accent, 0.18) : cardColor
                border.width: 1
                border.color: adapter && adapter.enabled ? host.withAlpha(accent, 0.35) : edgeColor

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8

                    Text {
                        text: "Bluetooth"
                        color: textColor
                        font.family: Style.font.family
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }

                    Text {
                        text: adapter && adapter.enabled ? (adapter.discovering ? "Scanning" : "On") : "Off"
                        color: mutedColor
                        font.family: Style.font.family
                        font.pixelSize: 11
                    }

                    MenuButton {
                        theme: page
                        label: "Toggle"
                        active: !!(adapter && adapter.enabled)
                        enabled: !!adapter
                        onClicked: toggleBluetooth()
                    }

                }

            }

        }

        Text {
            visible: !adapter
            text: "No Bluetooth adapter found"
            color: mutedColor
            font.family: Style.font.family
            font.pixelSize: 12
        }

        Flickable {
            id: bluetoothList

            Layout.fillWidth: true
            Layout.preferredWidth: page.width
            Layout.preferredHeight: Math.min(bluetoothContent.implicitHeight, 360)
            contentWidth: width
            contentHeight: bluetoothContent.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: bluetoothContent

                width: bluetoothList.width
                spacing: 12

                DeviceGroup {
                    title: "Connected"
                    entries: page.connectedBt
                    group: "connected"
                    page: page
                }

                DeviceGroup {
                    title: "Paired"
                    entries: page.pairedBt
                    group: "paired"
                    page: page
                }

                DeviceGroup {
                    title: "Nearby"
                    entries: page.availableBt
                    group: "nearby"
                    page: page
                }

            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

        }

        Text {
            visible: adapter && adapter.enabled && bluetoothDevices.length === 0
            text: adapter && adapter.discovering ? "Searching for devices…" : "No devices found yet"
            color: mutedColor
            font.family: Style.font.family
            font.pixelSize: 11
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

    }

    Text {
        visible: notice !== ""
        text: notice
        color: host.colorUrgent
        font.family: Style.font.family
        font.pixelSize: 11
        Layout.fillWidth: true
    }

    component MenuButton: Rectangle {
        id: button

        required property var theme
        property string label: ""
        property string hint: ""
        property bool active: false

        signal clicked()

        implicitWidth: labelText.implicitWidth + 20
        implicitHeight: 30
        radius: 10
        color: !enabled ? "transparent" : active ? theme.host.withAlpha(theme.accent, 0.24) : mouse.containsMouse ? theme.hoverColor : theme.cardColor
        border.width: active ? 1 : 0
        border.color: theme.host.withAlpha(theme.accent, 0.38)
        opacity: enabled ? 1 : 0.45

        Text {
            id: labelText

            anchors.centerIn: parent
            text: button.label
            color: button.active ? theme.accentText : theme.textColor
            font.family: Style.font.family
            font.pixelSize: 10
            font.weight: button.active ? Font.DemiBold : Font.Medium
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            enabled: button.enabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: button.clicked()
        }

        Behavior on color {
            ColorAnimation {
                duration: 130 * theme.host.motionScale
            }

        }

    }

    component DeviceGroup: Column {
        id: groupView

        required property string title
        required property var entries
        required property string group
        required property var page

        visible: entries.length > 0
        width: parent ? parent.width : 0
        spacing: 6

        Text {
            text: groupView.title
            color: groupView.page.mutedColor
            font.family: Style.font.family
            font.pixelSize: 10
            font.weight: Font.DemiBold
            x: 3
        }

        Repeater {
            model: groupView.entries

            delegate: Rectangle {
                required property var modelData

                width: groupView.width
                height: 68
                radius: 11
                color: modelData.connected ? groupView.page.host.withAlpha(groupView.page.accent, 0.1) : deviceMouse.containsMouse ? groupView.page.hoverColor : groupView.page.cardColor
                border.width: modelData.connected ? 1 : 0
                border.color: groupView.page.host.withAlpha(groupView.page.accent, 0.28)

                MouseArea {
                    id: deviceMouse

                    anchors.fill: parent
                    z: 0
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    anchors.topMargin: 5
                    anchors.bottomMargin: 5
                    spacing: 2
                    z: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: modelData.connected ? "󰂱" : "󰂯"
                            color: modelData.connected ? groupView.page.accent : groupView.page.mutedColor
                            font.family: groupView.page.iconFont
                            font.pixelSize: 16
                        }

                        Text {
                            text: groupView.page.bluetoothLabel(modelData) || modelData.name || "Bluetooth device"
                            color: groupView.page.textColor
                            font.family: Style.font.family
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: groupView.page.pendingActions[modelData.address] || (modelData.pairing ? "Pairing…" : modelData.connected && modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "% battery" : modelData.connected ? "Connected" : groupView.group === "paired" ? "Saved device" : "Available to pair")
                            color: groupView.page.mutedColor
                            font.family: Style.font.family
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        MenuButton {
                            theme: groupView.page
                            label: modelData.connected ? "Disconnect" : "Connect"
                            active: modelData.connected
                            enabled: !!(groupView.page.adapter && groupView.page.adapter.enabled)
                            onClicked: groupView.page.bluetoothAction(modelData, modelData.connected ? "disconnect" : groupView.group === "nearby" ? "pair" : "connect")
                        }

                        MenuButton {
                            theme: groupView.page
                            visible: groupView.group !== "nearby"
                            label: "Forget"
                            onClicked: groupView.page.bluetoothAction(modelData, "forget")
                        }

                    }

                }

            }

        }

    }

}
