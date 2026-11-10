pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Qt.labs.folderlistmodel

ShellRoot {
  id: root
  // Every image in images/ is a scene; the installer fills that folder from
  // the theme's backgrounds, so new wallpapers join the rotation.
  FolderListModel {
    id: imageFiles
    folder: Qt.resolvedUrl("images/")
    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
    showDirs: false
    sortField: FolderListModel.Name
  }
  readonly property var scenes: {
    var list = []
    if (imageFiles.status !== FolderListModel.Ready) return list
    for (var i = 0; i < imageFiles.count; i++) {
      var file = imageFiles.get(i, "fileName")
      // "03-monarchs-gaze.jpg" → "MONARCHS GAZE"
      var name = file.replace(/\.[^.]+$/, "").replace(/^[0-9]+[-_ ]*/, "").replace(/[-_]+/g, " ")
      list.push({ file: file, title: "SOLO LEVELING", detail: name.toUpperCase() })
    }
    return list
  }
  readonly property var scene: scenes.length > 0 ? scenes[sceneIndex % scenes.length] : null
  property int sceneIndex: 0
  // Scene phases, all 0 → 1: rain lays pixels down, sharpen resolves them,
  // drain rains them away. clock only advances while pixels are moving.
  property real rain: 0
  property real sharpen: 0
  property real drain: 0
  property real clock: 0
  readonly property bool moving: !testFrame && ((rain > 0 && rain < 1) || drain > 0)
  property bool armed: false
  property bool testFrame: false
  readonly property int previewSeconds: Math.max(0, Number(Quickshell.env("SOLO_PREVIEW_SECONDS")) || 0)

  Timer { interval: 1200; running: true; onTriggered: root.armed = true }
  Timer {
    interval: Math.max(1, root.previewSeconds) * 1000
    running: root.previewSeconds > 0
    onTriggered: Qt.quit()
  }
  SequentialAnimation {
    running: !root.testFrame && root.scenes.length > 0
    loops: Animation.Infinite
    ScriptAction { script: { root.rain = 0; root.sharpen = 0; root.drain = 0 } }
    PauseAnimation { duration: 400 }
    NumberAnimation { target: root; property: "rain"; from: 0; to: 1; duration: 5200 }
    NumberAnimation { target: root; property: "sharpen"; from: 0; to: 1; duration: 2400; easing.type: Easing.InOutCubic }
    PauseAnimation { duration: 12000 }
    NumberAnimation { target: root; property: "sharpen"; from: 1; to: 0; duration: 2000; easing.type: Easing.InOutCubic }
    NumberAnimation { target: root; property: "drain"; from: 0; to: 1; duration: 4200 }
    PauseAnimation { duration: 300 }
    ScriptAction { script: root.sceneIndex = (root.sceneIndex + 1) % root.scenes.length }
  }
  NumberAnimation on clock {
    running: root.moving
    from: root.clock; to: root.clock + 3600; duration: 3600000; loops: 1
  }


  Variants {
    model: Quickshell.screens
    FloatingWindow {
      id: window
      required property var modelData
      screen: modelData
      title: "Solo Leveling Screensaver"
      color: "#07050e"
      fullscreen: true
      visible: true
      implicitWidth: modelData.width
      implicitHeight: modelData.height
      onClosed: Qt.quit()

      FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) { event.accepted = true; Qt.quit() }

        Image {
          id: artwork
          source: root.scene ? Qt.resolvedUrl("images/" + root.scene.file) : ""
          visible: false
          asynchronous: true
          onStatusChanged: if (status === Image.Error) Qt.quit()
        }
        ShaderEffect {
          anchors.fill: parent
          property variant source: artwork
          property vector2d viewportSize: Qt.vector2d(width, height)
          property real imageAspect: artwork.sourceSize.height > 0 ? artwork.sourceSize.width / artwork.sourceSize.height : 1.5
          property real rain: artwork.status === Image.Ready ? root.rain : 0
          property real sharpen: root.sharpen
          property real drain: root.drain
          property real time: root.clock
          property real seed: root.sceneIndex + 17
          fragmentShader: Qt.resolvedUrl("pixel-rain.frag.qsb")
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Math.min(210, parent.height * 0.23)
          gradient: Gradient {
            GradientStop { position: 0; color: "#00000000" }
            GradientStop { position: 1; color: "#c007050e" }
          }
          opacity: root.sharpen * (1 - root.drain)
        }
        Column {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: Math.min(48, window.width * 0.045)
          spacing: 9
          opacity: root.sharpen * (1 - root.drain)
          Text {
            text: root.scene ? root.scene.title : ""
            color: "#e2dbf4"
            font.family: "monospace"
            font.pixelSize: Math.min(27, window.width / 32)
            font.letterSpacing: 4
          }
          Text {
            text: root.scene ? root.scene.detail : ""
            color: "#9b7bff"
            font.family: "monospace"
            font.pixelSize: Math.min(11, window.width / 70)
            font.letterSpacing: 2
          }
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.BlankCursor
          property real lastX: -1
          property real lastY: -1
          onPressed: Qt.quit()
          onWheel: Qt.quit()
          onPositionChanged: function(mouse) {
            if (root.armed && lastX >= 0 && Math.hypot(mouse.x - lastX, mouse.y - lastY) > 3) Qt.quit()
            lastX = mouse.x
            lastY = mouse.y
          }
        }
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.armed && String(event.name) === "activewindow") {
        var data = String(event.data || "")
        if (data && !data.startsWith("org.omarchy.screensaver,")) Qt.quit()
      }
    }
  }

  IpcHandler {
    target: "screensaver"
    function quit(): void { Qt.quit() }
    function status(): string {
      return JSON.stringify({ scene: root.sceneIndex, title: root.scene ? root.scene.detail : "", scenes: root.scenes.length, rain: root.rain, sharpen: root.sharpen, drain: root.drain, screens: Quickshell.screens.length })
    }
    function frame(index: int, rain: real, sharpen: real, drain: real, clock: real): void {
      root.testFrame = true
      root.sceneIndex = Math.max(0, Math.min(Math.max(0, root.scenes.length - 1), index))
      root.rain = Math.max(0, Math.min(1, rain))
      root.sharpen = Math.max(0, Math.min(1, sharpen))
      root.drain = Math.max(0, Math.min(1, drain))
      root.clock = clock
    }
  }
}
