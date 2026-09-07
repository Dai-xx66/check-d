import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }

    delegate = self

    super.awakeFromNib()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Keep the main Flutter engine alive while the floating widget is open.
    // The normal close affordance becomes a hide; Dock re-open and the widget's
    // "open main app" action can then restore this exact window and engine.
    orderOut(nil)
    return false
  }
}
