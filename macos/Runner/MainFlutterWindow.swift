import Cocoa
import FlutterMacOS
import desktop_multi_window
import Vision

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let localOcrChannel = FlutterMethodChannel(
      name: "check_d/local_ocr",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    localOcrChannel.setMethodCallHandler { call, result in
      guard call.method == "recognize" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let typedBytes = arguments["bytes"] as? FlutterStandardTypedData,
        let image = NSImage(data: typedBytes.data),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
      else {
        result(FlutterError(code: "image_decode_failed", message: "无法读取图片", details: nil))
        return
      }
      let request = VNRecognizeTextRequest { request, error in
        if let error = error {
          result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
          return
        }
        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let tokens: [[String: Any]] = observations.compactMap { observation in
          guard let candidate = observation.topCandidates(1).first else { return nil }
          let box = observation.boundingBox
          return [
            "text": candidate.string,
            "left": Double(box.minX * width),
            "top": Double((1 - box.maxY) * height),
            "right": Double(box.maxX * width),
            "bottom": Double((1 - box.minY) * height),
            "confidence": Double(candidate.confidence),
          ]
        }
        result([
          "imageWidth": Double(cgImage.width),
          "imageHeight": Double(cgImage.height),
          "tokens": tokens,
        ])
      }
      request.recognitionLevel = .accurate
      request.recognitionLanguages = ["zh-Hans", "en-US"]
      request.usesLanguageCorrection = false
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
          result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      Self.installFloatingWidgetMaterial(on: controller)
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

  private static func installFloatingWidgetMaterial(on controller: FlutterViewController) {
    DispatchQueue.main.async {
      guard let window = controller.view.window else { return }
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = true

      controller.backgroundColor = .clear
      controller.view.wantsLayer = true
      controller.view.layer?.backgroundColor = NSColor.clear.cgColor
      controller.view.layer?.cornerRadius = 20
      controller.view.layer?.masksToBounds = true

      let material = NSVisualEffectView(frame: controller.view.bounds)
      material.identifier = NSUserInterfaceItemIdentifier("check-d-floating-material")
      material.autoresizingMask = [.width, .height]
      material.alphaValue = 0.82
      material.wantsLayer = true
      material.layer?.cornerRadius = 20
      material.layer?.masksToBounds = true
      material.material = .sidebar
      material.blendingMode = .behindWindow
      material.state = .active
      controller.view.addSubview(material, positioned: .below, relativeTo: nil)
      window.invalidateShadow()
    }
  }
}
