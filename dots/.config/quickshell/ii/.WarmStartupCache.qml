//@ pragma UseQApplication
//@ pragma Env QML_DISK_CACHE=qmlc-read,qmlc-write
import QtQuick
import Quickshell
import "modules/common"
import "services"
import "panelFamilies"
ShellRoot {
 Component.onCompleted: Qt.callLater(function() {
  for (const path of ["CoreDesktop.qml", "modules/ii/background/Background.qml", "modules/ii/bar/Bar.qml", "modules/ii/dynamicIsland/DynamicIsland.qml", "ShellRuntime.qml"]) {
   const c=Qt.createComponent(Qt.resolvedUrl(path), Component.PreferSynchronous);
   if (c.status !== Component.Ready) console.error("Cache warm-up:", path, c.errorString());
  }
  console.info("Cache warm-up complete");
  Qt.quit();
 })
}
