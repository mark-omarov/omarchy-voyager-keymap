import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property var settings: ({})
  readonly property string layoutRef: typeof root.settings.layout === "string" ? root.settings.layout : ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")

  function loadSettings(text) {
    var id = root.manifest ? root.manifest.id : "io.github.mark-omarov.voyager-keymap"
    try {
      var plugins = JSON.parse(text).plugins
      root.settings = (Array.isArray(plugins) ? plugins : []).filter(function(p) { return p && p.id === id })[0] || {}
    } catch (e) {
      root.settings = {}
    }
  }

  FileView {
    path: root.configHome + "/omarchy/shell.json"
    blockLoading: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadSettings(text())
  }

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/+$/, "")
  readonly property string helper: root.pluginDir + "/voyager-keymap"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property string cachePath: root.stateHome + "/voyager-keymap/layout.json"

  property var layout: null
  property string liveState: ""
  property int liveLayer: -1
  property int pickedLayer: -1
  property var pressedKeys: ({})
  property string fetchError: ""
  property bool practice: false
  property int detailKey: -1
  property int hoverKey: -1
  function settingKey(name, fallback) {
    return typeof root.settings[name] === "string" && root.settings[name] ? root.settings[name] : fallback
  }
  readonly property string toggleKey: root.settingKey("toggleKey", "SUPER + SHIFT + K")
  readonly property string practiceKey: root.settingKey("practiceKey", "SUPER + SHIFT + ALT + K")
  readonly property string moveKey: root.settingKey("moveKey", "SUPER + SHIFT + CTRL + K")

  readonly property int layerCount: root.layout ? root.layout.layers.length : 0
  readonly property int shownLayer: {
    var n = root.pickedLayer >= 0 ? root.pickedLayer : (root.liveLayer >= 0 ? root.liveLayer : 0)
    return Math.min(Math.max(0, n), Math.max(0, root.layerCount - 1))
  }
  readonly property var shownKeys: root.layerCount > 0 ? root.layout.layers[root.shownLayer].keys : []
  readonly property var shownCombos: root.layout && Array.isArray(root.layout.combos)
    ? root.layout.combos.filter(function(c) { return c.layer === root.shownLayer }) : []
  readonly property var comboKeys: {
    var keys = {}
    for (var i = 0; i < root.shownCombos.length; i++)
      for (var j = 0; j < root.shownCombos[i].keys.length; j++) keys[root.shownCombos[i].keys[j]] = true
    return keys
  }
  readonly property int focusKey: root.hoverKey >= 0 ? root.hoverKey : root.detailKey
  readonly property var focusInfo: root.focusKey >= 0 && root.focusKey < root.shownKeys.length ? root.shownKeys[root.focusKey] : null
  readonly property var focusCombos: root.shownCombos.filter(function(c) { return c.keys.indexOf(root.focusKey) >= 0 })

  function keyName(index) {
    var key = root.shownKeys[index]
    return key ? (key.tap || key.hold || "·") : "?"
  }

  function setPractice(on) {
    practiceProc.command = [root.helper, "practice", on ? "on" : "off",
      "--exit-key", root.practiceKey, "--close-key", root.toggleKey, "--move-key", root.moveKey]
    practiceProc.running = true
  }

  Process { id: practiceProc }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "submap") root.practice = String(event.data).indexOf("voyager-practice") === 0
    }
  }

  readonly property color shownColor: root.layerCount > 0 && root.layout.layers[root.shownLayer].color
    ? root.layout.layers[root.shownLayer].color : Commons.Color.accent

  // Key centre x, centre y, width, height (key units) and rotation, in Oryx key order.
  // Rows follow QMK's zsa/voyager stagger; the halves and angled thumbs follow Keymapp's drawing.
  readonly property var geometry: [
    [0.5, 1.0, 1, 1, 0], [1.5, 1.0, 1, 1, 0], [2.5, 0.75, 1, 1, 0], [3.5, 0.5, 1, 1, 0], [4.5, 0.75, 1, 1, 0], [5.5, 1.0, 1, 1, 0],
    [0.5, 2.0, 1, 1, 0], [1.5, 2.0, 1, 1, 0], [2.5, 1.75, 1, 1, 0], [3.5, 1.5, 1, 1, 0], [4.5, 1.75, 1, 1, 0], [5.5, 2.0, 1, 1, 0],
    [0.5, 3.0, 1, 1, 0], [1.5, 3.0, 1, 1, 0], [2.5, 2.75, 1, 1, 0], [3.5, 2.5, 1, 1, 0], [4.5, 2.75, 1, 1, 0], [5.5, 3.0, 1, 1, 0],
    [0.5, 4.0, 1, 1, 0], [1.5, 4.0, 1, 1, 0], [2.5, 3.75, 1, 1, 0], [3.5, 3.5, 1, 1, 0], [4.5, 3.75, 1, 1, 0], [5.5, 4.0, 1, 1, 0],
    [5.73, 5.3, 1, 1, 30], [6.5, 6.04, 1, 1.5, 30],
    [9.5, 1.0, 1, 1, 0], [10.5, 0.75, 1, 1, 0], [11.5, 0.5, 1, 1, 0], [12.5, 0.75, 1, 1, 0], [13.5, 1.0, 1, 1, 0], [14.5, 1.0, 1, 1, 0],
    [9.5, 2.0, 1, 1, 0], [10.5, 1.75, 1, 1, 0], [11.5, 1.5, 1, 1, 0], [12.5, 1.75, 1, 1, 0], [13.5, 2.0, 1, 1, 0], [14.5, 2.0, 1, 1, 0],
    [9.5, 3.0, 1, 1, 0], [10.5, 2.75, 1, 1, 0], [11.5, 2.5, 1, 1, 0], [12.5, 2.75, 1, 1, 0], [13.5, 3.0, 1, 1, 0], [14.5, 3.0, 1, 1, 0],
    [9.5, 4.0, 1, 1, 0], [10.5, 3.75, 1, 1, 0], [11.5, 3.5, 1, 1, 0], [12.5, 3.75, 1, 1, 0], [13.5, 4.0, 1, 1, 0], [14.5, 4.0, 1, 1, 0],
    [8.5, 6.04, 1, 1.5, -30], [9.27, 5.3, 1, 1, -30]
  ]

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property var dockSpots: [
    { x: 1, y: 0 }, { x: 1, y: 1 }, { x: 0.5, y: 1 }, { x: 0, y: 1 }, { x: 0, y: 0 }, { x: 0.5, y: 0 }
  ]

  function moveToNextSpot() {
    var best = 0, bestDistance = 99
    for (var i = 0; i < root.dockSpots.length; i++) {
      var d = Math.abs(root.dockSpots[i].x - root.view.x) + Math.abs(root.dockSpots[i].y - root.view.y)
      if (d < bestDistance) { best = i; bestDistance = d }
    }
    var next = root.dockSpots[(best + 1) % root.dockSpots.length]
    root.view = { x: next.x, y: next.y, scale: root.view.scale }
    root.saveView()
  }

  function open(payload) {
    var request = {}
    try { request = JSON.parse(payload || "{}") || {} } catch (e) {}
    if (request.action === "practice" || request.action === "move") {
      if (!root.opened) {
        root.opened = true
        root.refresh()
        if (request.action === "practice") root.setPractice(true)
        return
      }
      if (request.action === "practice") root.setPractice(!root.practice)
      else root.moveToNextSpot()
      return
    }
    root.opened = true
    root.pickedLayer = typeof request.layer === "number" ? Math.max(0, Math.floor(request.layer)) : -1
    root.detailKey = -1
    root.refresh()
    if (request.practice === true) root.setPractice(true)
  }

  function close() {
    root.opened = false
  }

  property bool refetch: false

  function refresh() {
    if (fetchProc.running) {
      root.refetch = true
      return
    }
    fetchProc.command = root.layoutRef
      ? [root.helper, "fetch", "--layout", root.layoutRef]
      : [root.helper, "fetch"]
    fetchProc.running = true
  }

  onLayoutRefChanged: if (root.opened) root.refresh()

  function loadCache(text) {
    try {
      var model = JSON.parse(text)
      if (model && Array.isArray(model.layers) && model.layers.length > 0) root.layout = model
    } catch (e) {
      console.warn("voyager-keymap: unreadable cache " + root.cachePath)
    }
  }

  function setPressed(index, down) {
    var next = Object.assign({}, root.pressedKeys)
    if (down) next[index] = true
    else delete next[index]
    root.pressedKeys = next
  }

  function liveLine(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (typeof msg.state === "string") {
      root.liveState = msg.state
      root.liveLayer = typeof msg.layer === "number" ? msg.layer : -1
      root.pressedKeys = {}
    } else if (typeof msg.key === "number") {
      root.setPressed(msg.key, msg.down === true)
      if (msg.down === true) root.detailKey = msg.key
    } else if (typeof msg.layer === "number" && msg.layer !== root.liveLayer) {
      root.liveLayer = msg.layer
      root.pickedLayer = -1
    }
  }

  readonly property string statusText: {
    if (fetchProc.running && !root.layout) return strings.t("status.fetching")
    switch (root.liveState) {
      case "connected": return strings.t("status.live")
      case "read-only": return strings.t("status.readOnly")
      case "no-keyboard": return strings.t("status.noKeyboard")
      case "no-access": return strings.t("status.noAccess")
      default: return strings.t("status.starting")
    }
  }

  readonly property string footerText: {
    if (root.fetchError) return strings.t("error.fetch").arg(root.fetchError)
    if (!root.layout) return ""
    var key = root.layout.source === "keymapp" ? "footer.source.keymapp" : "footer.source.oryx"
    return strings.t(key).arg(String(root.layout.revisionAt || "?"))
  }

  FileView {
    path: root.cachePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadCache(text())
  }

  Process {
    id: fetchProc
    onExited: if (root.refetch) {
      root.refetch = false
      Qt.callLater(root.refresh)
    }
    stdout: StdioCollector {
      onStreamFinished: {
        var msg
        try { msg = JSON.parse(text) } catch (e) { msg = { ok: false, error: "no output" } }
        root.fetchError = msg.ok ? "" : String(msg.error || "unknown error").slice(0, 160)
      }
    }
  }

  Process {
    id: watchProc
    command: [root.helper, "watch"]
    stdout: SplitParser { onRead: function(line) { root.liveLine(line) } }
  }

  Timer {
    interval: 2000
    repeat: true
    triggeredOnStart: true
    running: root.opened
    onTriggered: if (!watchProc.running) watchProc.running = true
  }

  onOpenedChanged: if (!root.opened) {
    if (root.practice) Quickshell.execDetached([root.helper, "practice", "off"])
    root.hoverKey = -1
    watchProc.running = false
    root.liveState = ""
    root.liveLayer = -1
    root.pressedKeys = {}
  }

  function onColor(c) {
    var l = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    return l > 0.55 ? "#141414" : "#ffffff"
  }

  property var view: ({ x: 1, y: 0, scale: 1 })
  readonly property string viewPath: root.stateHome + "/voyager-keymap/view.json"

  function saveView() {
    viewFile.setText(JSON.stringify(root.view))
  }

  FileView {
    id: viewFile
    path: root.viewPath
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var v = JSON.parse(text())
        root.view = {
          x: isFinite(Number(v.x)) ? Math.min(1, Math.max(0, Number(v.x))) : 1,
          y: isFinite(Number(v.y)) ? Math.min(1, Math.max(0, Number(v.y))) : 0,
          scale: Math.min(1.6, Math.max(0.5, Number(v.scale) || 1))
        }
      } catch (e) {}
    }
  }

  readonly property string focusSummary: {
    var k = root.focusInfo
    if (!k || k.none) return ""
    var parts = []
    var details = Array.isArray(k.details) ? k.details : []
    for (var i = 0; i < details.length; i++) parts.push(details[i][0] + ":  " + details[i][1])
    for (var j = 0; j < root.focusCombos.length; j++)
      parts.push(strings.t("detail.combo") + ":  " + root.focusCombos[j].keys.map(root.keyName).join(" + ") + " → " + root.focusCombos[j].label)
    return parts.join("\n")
  }

  readonly property string combosSummary: root.shownCombos.map(function(c) {
    return c.keys.map(root.keyName).join(" + ") + " → " + c.label
  }).join("\n")

  OverlayWindow {
    id: window
    shown: root.opened
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "voyager-keymap"
    mask: Region { item: card }

    Rectangle {
      id: card

      readonly property real unit: Math.floor(Math.min(window.width * 0.45, Style.space(1040)) * root.view.scale / 15.6)
      readonly property real pad: Math.round(unit * 0.3)
      readonly property real gap: Math.max(3, Math.round(unit * 0.07))
      readonly property real margin: Style.gapsOut * 4
      readonly property color ink: Commons.Color.menu.text

      width: unit * 15 + pad * 2
      height: pad + header.height + Math.round(unit * 0.3) + board.height + pad
      x: margin + Math.max(0, window.width - width - margin * 2) * root.view.x
      y: margin + Math.max(0, window.height - height - margin * 2) * root.view.y
      color: Commons.Color.menu.background
      border.width: Math.max(1, Style.space(root.practice ? 3 : 1))
      border.color: root.practice ? Commons.Color.accent : Commons.Util.alpha(card.ink, 0.12)
      radius: Style.cornerRadius
      clip: true

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(3, Math.round(card.unit * 0.05))
        color: root.shownColor
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point grab
        onPressed: function(mouse) { grab = Qt.point(mouse.x, mouse.y) }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var freeX = Math.max(1, window.width - card.width - card.margin * 2)
          var freeY = Math.max(1, window.height - card.height - card.margin * 2)
          var nx = card.x + mouse.x - grab.x - card.margin
          var ny = card.y + mouse.y - grab.y - card.margin
          root.view = { x: Math.min(1, Math.max(0, nx / freeX)), y: Math.min(1, Math.max(0, ny / freeY)), scale: root.view.scale }
        }
        onReleased: root.saveView()
        onWheel: function(wheel) {
          var step = wheel.angleDelta.y > 0 ? 0.08 : -0.08
          root.view = { x: root.view.x, y: root.view.y, scale: Math.min(1.6, Math.max(0.5, root.view.scale + step)) }
          root.saveView()
        }
      }

      component TextButton: Text {
        id: button
        signal clicked()
        property bool active: false
        textFormat: Text.PlainText
        color: active ? Commons.Color.accent : Commons.Util.alpha(card.ink, buttonArea.containsMouse ? 0.9 : 0.5)
        font.family: Style.font.menuFamily
        font.pixelSize: Math.round(card.unit * 0.2)
        font.weight: active ? Font.DemiBold : Font.Normal
        MouseArea {
          id: buttonArea
          anchors.fill: parent
          anchors.margins: -Math.round(card.unit * 0.1)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: button.clicked()
        }
      }

      Item {
        id: header
        x: card.pad
        y: card.pad
        width: card.width - card.pad * 2
        height: Math.round(card.unit * 0.5)

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Math.round(card.unit * 0.08)

          Repeater {
            model: root.layout ? root.layout.layers : []

            Rectangle {
              id: tab
              required property var modelData
              required property int index
              readonly property bool current: index === root.shownLayer
              readonly property color layerColor: modelData.color || Commons.Color.accent

              width: tabRow.implicitWidth + Math.round(card.unit * 0.28)
              height: Math.round(card.unit * 0.42)
              radius: height / 2
              color: current ? layerColor : tabArea.containsMouse ? Commons.Util.alpha(card.ink, 0.08) : "transparent"

              Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: Math.round(card.unit * 0.08)

                Rectangle {
                  visible: !tab.current
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.round(card.unit * 0.12)
                  height: width
                  radius: width / 2
                  color: tab.layerColor
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: tab.modelData.title
                  color: tab.current ? root.onColor(tab.layerColor) : Commons.Util.alpha(card.ink, 0.7)
                  font.family: Style.font.menuFamily
                  font.pixelSize: Math.round(card.unit * 0.21)
                  font.weight: tab.current ? Font.DemiBold : Font.Normal
                }
              }

              MouseArea {
                id: tabArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pickedLayer = tab.index
              }
            }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Math.round(card.unit * 0.32)

          Text {
            visible: root.liveState !== "" && root.liveState !== "connected"
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.statusText
            color: Commons.Util.alpha(card.ink, 0.45)
            font.family: Style.font.menuFamily
            font.pixelSize: Math.round(card.unit * 0.17)
          }

          TextButton {
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t(root.practice ? "practice.on" : "practice.off")
            active: root.practice
            onClicked: root.setPractice(!root.practice)
          }

          TextButton {
            anchors.verticalCenter: parent.verticalCenter
            text: "✕"
            onClicked: root.close()
          }
        }
      }

      Item {
        id: board
        x: card.pad
        y: header.y + header.height + Math.round(card.unit * 0.3)
        width: card.unit * 15
        height: card.unit * 6.9

        Column {
          x: card.unit * 6.12
          y: card.unit * 0.25
          width: card.unit * 2.76
          spacing: Math.round(card.unit * 0.18)

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.layerCount > 0 ? root.layout.layers[root.shownLayer].title : ""
            color: root.shownColor
            font.family: Style.font.menuFamily
            font.pixelSize: Math.round(card.unit * 0.36)
            font.weight: Font.Bold
          }

          Text {
            width: parent.width
            horizontalAlignment: root.focusSummary !== "" ? Text.AlignLeft : Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.25
            textFormat: Text.PlainText
            text: root.practice ? strings.t("practice.hint").arg(root.practiceKey)
              : root.focusSummary !== "" ? root.focusSummary
              : root.combosSummary !== "" ? strings.t("detail.combos") + "\n" + root.combosSummary
              : root.layout ? strings.t("detail.hint") : ""
            color: root.practice ? Commons.Color.accent : Commons.Util.alpha(card.ink, root.focusSummary !== "" ? 0.9 : 0.45)
            font.family: Style.font.menuFamily
            font.pixelSize: Math.round(card.unit * 0.17)
          }
        }

        Repeater {
          model: root.shownKeys.length === 52 ? root.shownKeys : []

          Item {
            id: key
            required property var modelData
            required property int index
            readonly property var g: root.geometry[index]
            readonly property bool down: root.pressedKeys[index] === true
            readonly property bool none: modelData.none === true
            readonly property bool through: modelData.through === true
            readonly property bool hovered: index === root.hoverKey
            readonly property bool isLayer: typeof modelData.layer === "number"
            readonly property color layerColor: modelData.layerColor || Commons.Color.accent
            readonly property bool lit: !!modelData.glow
            readonly property color led: modelData.glow || "transparent"
            readonly property color ink: down ? root.onColor(Commons.Color.accent) : card.ink
            readonly property string holdText: modelData.hold ? modelData.hold
              : modelData.tapHold ? strings.t("key.tapHold") + " " + modelData.tapHold : ""
            readonly property string tag: modelData.macro === true ? strings.t("key.macro")
              : root.comboKeys[index] === true ? strings.t("key.combo") : ""
            readonly property real radius: Math.round(card.unit * 0.07)

            x: (g[0] - g[2] / 2) * card.unit + card.gap / 2
            y: (g[1] - g[3] / 2) * card.unit + card.gap / 2
            width: g[2] * card.unit - card.gap
            height: g[3] * card.unit - card.gap
            rotation: g[4]

            RectangularShadow {
              anchors.fill: parent
              radius: key.radius
              visible: key.lit || key.down
              color: key.down ? Commons.Color.accent : key.led
              blur: card.unit * 0.16
              spread: 0
              opacity: key.down ? 0.8 : 0.45
            }

            Rectangle {
              anchors.fill: parent
              radius: key.radius
              color: Commons.Color.menu.background
              border.width: 1
              border.color: key.down ? Commons.Color.accent
                : key.lit ? Commons.Util.alpha(key.led, 0.5)
                : Commons.Util.alpha(card.ink, 0.1)

              Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.max(0, key.radius - 1)
                color: key.down ? Commons.Color.accent
                  : key.lit ? Commons.Util.alpha(key.led, key.hovered ? 0.22 : 0.1)
                  : Commons.Util.alpha(card.ink, key.hovered ? 0.1 : 0.04)
                Behavior on color { ColorAnimation { duration: Style.duration(80) } }
              }
            }

            Rectangle {
              visible: !!modelData.swatch
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: Math.round(card.unit * 0.1)
              width: Math.round(card.unit * 0.12)
              height: width
              radius: width / 2
              color: modelData.swatch || "transparent"
            }

            Text {
              visible: key.tag !== "" && !key.none
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.topMargin: Math.round(card.unit * 0.06)
              anchors.leftMargin: Math.round(card.unit * 0.08)
              textFormat: Text.PlainText
              text: key.tag
              color: Commons.Util.alpha(key.ink, 0.65)
              font.family: Style.font.menuFamily
              font.pixelSize: Math.round(card.unit * 0.145)
            }

            Text {
              visible: !!modelData.double && !key.none
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.topMargin: Math.round(card.unit * 0.06)
              anchors.rightMargin: Math.round(card.unit * 0.08)
              textFormat: Text.PlainText
              text: "2× " + (modelData.double || "")
              color: Commons.Util.alpha(key.ink, 0.6)
              font.family: Style.font.menuFamily
              font.pixelSize: Math.round(card.unit * 0.14)
            }

            Text {
              visible: !key.none
              anchors.fill: parent
              anchors.leftMargin: Math.round(card.unit * 0.06)
              anchors.rightMargin: Math.round(card.unit * 0.06)
              anchors.topMargin: key.tag || modelData.double ? Math.round(card.unit * 0.2) : Math.round(card.unit * 0.08)
              anchors.bottomMargin: key.holdText ? Math.round(card.unit * 0.32) : Math.round(card.unit * 0.08)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              fontSizeMode: Text.Fit
              minimumPixelSize: 8
              textFormat: Text.PlainText
              text: modelData.tap
              color: key.down ? key.ink
                : key.isLayer && !key.holdText ? Qt.lighter(key.layerColor, 1.25)
                : Commons.Util.alpha(card.ink, key.through ? 0.35 : 0.95)
              font.family: Style.font.menuFamily
              font.pixelSize: Math.round(card.unit * (text.length <= 2 ? 0.34 : text.length <= 3 ? 0.27 : 0.21))
              font.weight: key.isLayer && !key.holdText ? Font.DemiBold : Font.Medium
            }

            Text {
              visible: key.holdText !== "" && !key.none
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: Math.round(card.unit * 0.05)
              anchors.rightMargin: Math.round(card.unit * 0.05)
              anchors.bottomMargin: Math.round(card.unit * 0.09)
              horizontalAlignment: Text.AlignHCenter
              fontSizeMode: Text.HorizontalFit
              minimumPixelSize: 8
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: key.holdText
              color: key.down ? Commons.Util.alpha(key.ink, 0.85)
                : key.isLayer ? Qt.lighter(key.layerColor, 1.25)
                : Commons.Util.alpha(card.ink, key.through ? 0.3 : 0.7)
              font.family: Style.font.menuFamily
              font.pixelSize: Math.round(card.unit * 0.19)
              font.weight: key.isLayer ? Font.DemiBold : Font.Normal
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
              onEntered: root.hoverKey = key.index
              onExited: if (root.hoverKey === key.index) root.hoverKey = -1
            }
          }
        }

        Column {
          visible: !root.layout
          anchors.centerIn: parent
          width: parent.width * 0.7
          spacing: Style.spacing.md

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: strings.t("empty.title")
            color: card.ink
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.fetchError ? root.footerText : strings.t("empty.body")
            color: Commons.Color.muted
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
