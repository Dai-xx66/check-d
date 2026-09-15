import Flutter
import ImageIO
import UIKit
import Vision

final class LocalOcrPlugin {
  private static let channelName = "check_d/local_ocr"
  private static let workQueue = DispatchQueue(
    label: "com.daixx66.checkd.local-ocr",
    qos: .userInitiated
  )

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let typedData = arguments["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(
          code: "image_decode_failed",
          message: "无法读取图片数据",
          details: nil
        ))
        return
      }

      recognize(typedData.data, result: result)
    }
  }

  static func recognize(_ data: Data, result: @escaping FlutterResult) {
    workQueue.async {
      autoreleasepool {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
          finish(result, errorCode: "image_decode_failed", message: "无法读取图片")
          return
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let imageSize = orientedSize(
          width: cgImage.width,
          height: cgImage.height,
          orientation: orientation
        )
        let request = VNRecognizeTextRequest { request, error in
          if let error {
            NSLog("Check D local OCR recognition failed: %@", error.localizedDescription)
            finish(result, errorCode: "ocr_recognition_failed", message: "本地 OCR 识别失败")
            return
          }

          let observations = request.results as? [VNRecognizedTextObservation] ?? []
          let tokens = observations.compactMap { observation -> OcrToken? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OcrToken(
              text: candidate.string,
              confidence: Double(candidate.confidence),
              box: pixelBox(observation.boundingBox, imageSize: imageSize)
            )
          }
          finish(result, value: [
            "imageWidth": imageSize.width,
            "imageHeight": imageSize.height,
            "tokens": readingOrder(tokens).map(\.channelValue),
          ])
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        do {
          let supportedLanguages = try request.supportedRecognitionLanguages()
          let preferredLanguages = ["zh-Hans", "en-US"].filter(supportedLanguages.contains)
          if !preferredLanguages.isEmpty {
            request.recognitionLanguages = preferredLanguages
          }
        } catch {
          NSLog("Check D local OCR language discovery failed: %@", error.localizedDescription)
        }
        do {
          try VNImageRequestHandler(
            cgImage: cgImage,
            orientation: orientation,
            options: [:]
          ).perform([request])
        } catch {
          NSLog("Check D local OCR request failed: %@", error.localizedDescription)
          finish(result, errorCode: "ocr_recognition_failed", message: "本地 OCR 识别失败")
        }
      }
    }
  }

  private static func finish(_ result: @escaping FlutterResult, value: Any) {
    DispatchQueue.main.async { result(value) }
  }

  private static func finish(
    _ result: @escaping FlutterResult,
    errorCode: String,
    message: String
  ) {
    DispatchQueue.main.async {
      result(FlutterError(code: errorCode, message: message, details: nil))
    }
  }

  static func orientedSize(
    width: Int,
    height: Int,
    orientation: CGImagePropertyOrientation
  ) -> CGSize {
    switch orientation {
    case .left, .leftMirrored, .right, .rightMirrored:
      return CGSize(width: height, height: width)
    default:
      return CGSize(width: width, height: height)
    }
  }

  private static func pixelBox(_ box: CGRect, imageSize: CGSize) -> CGRect {
    CGRect(
      x: box.minX * imageSize.width,
      y: (1 - box.maxY) * imageSize.height,
      width: box.width * imageSize.width,
      height: box.height * imageSize.height
    )
  }

  static func readingOrder(_ tokens: [OcrToken]) -> [OcrToken] {
    let topFirst = tokens.sorted {
      if $0.box.minY == $1.box.minY { return $0.box.minX < $1.box.minX }
      return $0.box.minY < $1.box.minY
    }
    var lines: [[OcrToken]] = []
    for token in topFirst {
      if let index = lines.indices.last,
         belongsToSameLine(token, as: lines[index]) {
        lines[index].append(token)
      } else {
        lines.append([token])
      }
    }
    return lines.flatMap { $0.sorted { $0.box.minX < $1.box.minX } }
  }

  private static func belongsToSameLine(_ token: OcrToken, as line: [OcrToken]) -> Bool {
    guard let first = line.first else { return false }
    let tolerance = max(first.box.height, token.box.height) * 0.6
    return abs(first.box.midY - token.box.midY) <= tolerance
  }
}

struct OcrToken {
  let text: String
  let confidence: Double
  let box: CGRect

  var channelValue: [String: Any] {
    [
      "text": text,
      "left": box.minX,
      "top": box.minY,
      "right": box.maxX,
      "bottom": box.maxY,
      "confidence": confidence,
    ]
  }
}

private extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
