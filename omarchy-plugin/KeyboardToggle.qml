import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui

// Shows or hides zenbook-duo-keyboard (README section 10); lit while the
// keyboard is up. Only present while the physical keyboard is undocked,
// which is when the dock watcher has the bottom screen (eDP-2) on.
BarWidget {
  id: root
  moduleName: "io.github.scrambletools.zenbook-duo-keyboard"

  // zenbook-duo-osk also moves workspaces off the bottom screen while the
  // keyboard covers it, and back afterwards.
  readonly property string toggleCommand: "\"$HOME/.config/zenbook/zenbook-duo-osk\" toggle"
  readonly property bool bottomScreenOn: {
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++)
      if (monitors[i].name === "eDP-2") return true
    return false
  }
  property bool keyboardShown: false

  visible: bottomScreenOn
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: probe
    // Process names are cut to 15 characters: zenbook-duo-keyboard -> zenbook-duo-key.
    command: ["pgrep", "-x", "zenbook-duo-key"]
    onExited: function(exitCode) { root.keyboardShown = exitCode === 0 }
  }

  // The keyboard can also be opened or closed elsewhere (Super+Ctrl+K, its
  // own hide key), so poll; pgrep every 2 s is cheap.
  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: probe.running = true
  }

  Timer {
    id: recheck
    interval: 500
    onTriggered: probe.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    active: root.keyboardShown
    tooltipText: root.keyboardShown ? "Hide on-screen keyboard" : "Show on-screen keyboard"
    onPressed: function(b) {
      root.bar.run(root.toggleCommand)
      recheck.restart()
    }
  }
}
