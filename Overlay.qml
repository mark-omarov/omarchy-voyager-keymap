import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
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
  property string liveKeyboard: ""
  property int liveLayer: -1
  property int pickedLayer: -1
  property string fetchError: ""

  readonly property int layerCount: root.layout ? root.layout.layers.length : 0
  readonly property int shownLayer: {
    var n = root.pickedLayer >= 0 ? root.pickedLayer : (root.liveLayer >= 0 ? root.liveLayer : 0)
    return Math.min(Math.max(0, n), Math.max(0, root.layerCount - 1))
  }
  readonly property var shownKeys: root.layerCount > 0 ? root.layout.layers[root.shownLayer].keys : []

  // Voyager key centres in key units, indexed like Oryx's key list (QMK zsa/voyager k00..k51).
  readonly property var geometry: [
    [0, 0.5], [1, 0.5], [2, 0.25], [3, 0], [4, 0.25], [5, 0.5],
    [0, 1.5], [1, 1.5], [2, 1.25], [3, 1], [4, 1.25], [5, 1.5],
    [0, 2.5], [1, 2.5], [2, 2.25], [3, 2], [4, 2.25], [5, 2.5],
    [0, 3.5], [1, 3.5], [2, 3.25], [3, 3], [4, 3.25], [5, 3.5],
    [5, 4.5], [6, 4.75],
    [10, 0.5], [11, 0.25], [12, 0], [13, 0.25], [14, 0.5], [15, 0.5],
    [10, 1.5], [11, 1.25], [12, 1], [13, 1.25], [14, 1.5], [15, 1.5],
    [10, 2.5], [11, 2.25], [12, 2], [13, 2.25], [14, 2.5], [15, 2.5],
    [10, 3.5], [11, 3.25], [12, 3], [13, 3.25], [14, 3.5], [15, 3.5],
    [9, 4.75], [10, 4.5]
  ]

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function open(payload) {
    var request = {}
    try { request = JSON.parse(payload || "{}") || {} } catch (e) {}
    root.opened = true
    root.pickedLayer = typeof request.layer === "number" ? Math.max(0, Math.floor(request.layer)) : -1
    root.refresh()
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

  function liveLine(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    root.liveState = String(msg.state || "")
    root.liveKeyboard = String(msg.keyboard || "")
    var layer = typeof msg.layer === "number" ? msg.layer : -1
    if (layer !== root.liveLayer) {
      root.liveLayer = layer
      root.pickedLayer = -1
    }
  }

  readonly property string statusText: {
    if (fetchProc.running && !root.layout) return strings.t("status.fetching")
    switch (root.liveState) {
      case "connected": return strings.t("status.live").arg(root.liveKeyboard)
      case "no-keyboard": return strings.t("status.noKeyboard")
      case "no-keymapp": return strings.t("status.noKeymapp")
      case "no-uv": return strings.t("status.noUv")
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
    watchProc.running = false
    root.liveState = ""
    root.liveLayer = -1
  }

  OverlayWindow {
    id: window
    shown: root.opened
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "voyager-keymap"
    mask: Region { item: card }

    Rectangle {
      id: card

      readonly property int pad: Style.spacing.panelPadding
      readonly property real unit: Math.floor((Math.min(window.width * 0.62, Style.space(1180)) - pad * 2) / 16)
      readonly property real gap: Math.max(2, Math.round(unit * 0.08))

      width: unit * 16 + pad * 2
      height: pad + header.height + Style.spacing.lg + board.height + Style.spacing.md + footer.height + pad
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.gapsOut * 4
      color: Commons.Color.menu.background
      border.color: Commons.Color.menu.border
      border.width: Math.max(1, Style.space(2))
      radius: Style.cornerRadius

      Item {
        id: header
        x: card.pad
        y: card.pad
        width: card.width - card.pad * 2
        height: Math.max(title.implicitHeight, tabs.height)

        Text {
          id: title
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width * 0.25)
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: root.layout ? root.layout.title : ""
          color: Commons.Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Row {
          id: tabs
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Repeater {
            model: root.layout ? root.layout.layers : []

            Rectangle {
              required property var modelData
              required property int index
              readonly property bool current: index === root.shownLayer
              readonly property bool live: index === root.liveLayer

              width: tabText.implicitWidth + Style.spacing.xl * 2
              height: tabText.implicitHeight + Style.spacing.sm * 2
              radius: Style.cornerRadius
              color: current ? Style.selectedAccentFill : "transparent"
              border.width: live ? 1 : 0
              border.color: Commons.Color.accent

              Text {
                id: tabText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.title
                color: parent.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pickedLayer = parent.index
              }
            }
          }
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width * 0.25)
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: root.statusText
          color: root.liveState === "connected" ? Commons.Color.accent : Commons.Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Item {
        id: board
        x: card.pad
        y: header.y + header.height + Style.spacing.lg
        width: card.unit * 16
        height: card.unit * 5.75

        Repeater {
          model: root.shownKeys.length === 52 ? root.shownKeys : []

          Rectangle {
            required property var modelData
            required property int index
            readonly property bool isLayerKey: typeof modelData.layer === "number"

            x: root.geometry[index][0] * card.unit + card.gap / 2
            y: root.geometry[index][1] * card.unit + card.gap / 2
            width: card.unit - card.gap
            height: card.unit - card.gap
            radius: Math.max(Style.cornerRadius, Math.round(card.unit * 0.12))
            color: modelData.transparent ? "transparent" : Style.normalFill
            border.width: 1
            border.color: isLayerKey ? Commons.Color.accent : Style.normalBorderColor
            opacity: modelData.transparent ? 0.45 : 1

            Rectangle {
              visible: !!modelData.swatch
              anchors.fill: parent
              anchors.margins: parent.height * 0.18
              radius: parent.radius
              color: modelData.swatch || "transparent"
              opacity: 0.55
            }

            Text {
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.spacing.xs
              width: parent.width * 0.7
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideLeft
              textFormat: Text.PlainText
              text: modelData.double ? "2× " + modelData.double : ""
              color: Commons.Color.muted
              font.family: Style.font.menuFamily
              font.pixelSize: Math.max(8, Math.round(card.unit * 0.15))
            }

            Text {
              anchors.fill: parent
              anchors.margins: Style.spacing.sm
              anchors.bottomMargin: modelData.hold ? card.unit * 0.28 : Style.spacing.sm
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              wrapMode: Text.WordWrap
              maximumLineCount: 3
              fontSizeMode: Text.Fit
              minimumPixelSize: 7
              textFormat: Text.PlainText
              text: modelData.transparent ? (modelData.through || "") : modelData.tap
              color: isLayerKey && modelData.tap && !modelData.hold ? Commons.Color.accent : Commons.Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Math.round(card.unit * (text.length <= 2 ? 0.34 : 0.22))
            }

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.spacing.xs
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: modelData.hold || modelData.tapHold || ""
              color: isLayerKey ? Commons.Color.accent : Commons.Color.muted
              font.family: Style.font.menuFamily
              font.pixelSize: Math.max(8, Math.round(card.unit * 0.16))
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
            color: Commons.Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: strings.t("empty.body")
            color: Commons.Color.muted
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      Text {
        id: footer
        x: card.pad
        y: board.y + board.height + Style.spacing.md
        width: card.width - card.pad * 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.footerText
        color: root.fetchError ? Commons.Color.urgent : Commons.Color.muted
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
