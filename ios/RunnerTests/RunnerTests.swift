import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testLocalOcrAcceptsPngAndJpegBytes() throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image { context in
      UIColor.white.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
    }
    let expectedWidth = CGFloat(try XCTUnwrap(image.cgImage).width)
    let expectedHeight = CGFloat(try XCTUnwrap(image.cgImage).height)
    let fixtures = [try XCTUnwrap(image.pngData()), try XCTUnwrap(image.jpegData(compressionQuality: 0.9))]

    for data in fixtures {
      let completed = expectation(description: "Vision returned a result")
      LocalOcrPlugin.recognize(data) { value in
        let payload = value as? [String: Any]
        XCTAssertEqual(payload?["imageWidth"] as? CGFloat, expectedWidth)
        XCTAssertEqual(payload?["imageHeight"] as? CGFloat, expectedHeight)
        XCTAssertNotNil(payload?["tokens"] as? [[String: Any]])
        completed.fulfill()
      }
      wait(for: [completed], timeout: 20)
    }
  }

  func testLocalOcrRejectsInvalidImageBytes() {
    let completed = expectation(description: "Invalid image rejected")
    LocalOcrPlugin.recognize(Data([0x00, 0x01])) { value in
      let error = value as? FlutterError
      XCTAssertEqual(error?.code, "image_decode_failed")
      completed.fulfill()
    }
    wait(for: [completed], timeout: 5)
  }

  func testLocalOcrRecognizesChineseCourseText() throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 180)).image { context in
      UIColor.white.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 640, height: 180))
      ("星期一\n高等数学" as NSString).draw(
        at: CGPoint(x: 32, y: 28),
        withAttributes: [
          .font: UIFont.systemFont(ofSize: 44, weight: .medium),
          .foregroundColor: UIColor.black,
        ]
      )
    }
    let data = try XCTUnwrap(image.pngData())
    let completed = expectation(description: "Chinese text recognized")

    LocalOcrPlugin.recognize(data) { value in
      let payload = value as? [String: Any]
      let tokens = payload?["tokens"] as? [[String: Any]] ?? []
      let text = tokens.compactMap { $0["text"] as? String }.joined(separator: "\n")
      XCTAssertTrue(text.contains("高等数学"), "Recognized text: \(text)")
      completed.fulfill()
    }
    wait(for: [completed], timeout: 20)
  }

  func testLocalOcrReadingOrderIsTopToBottomThenLeftToRight() {
    let tokens = [
      OcrToken(text: "右上", confidence: 1, box: CGRect(x: 200, y: 20, width: 50, height: 20)),
      OcrToken(text: "下一行", confidence: 1, box: CGRect(x: 10, y: 90, width: 80, height: 20)),
      OcrToken(text: "左上", confidence: 1, box: CGRect(x: 10, y: 18, width: 50, height: 20)),
    ]

    XCTAssertEqual(
      LocalOcrPlugin.readingOrder(tokens).map(\.text),
      ["左上", "右上", "下一行"]
    )
  }

  func testLocalOcrOrientationSwapsSidewaysImageDimensions() {
    XCTAssertEqual(
      LocalOcrPlugin.orientedSize(width: 1200, height: 800, orientation: .right),
      CGSize(width: 800, height: 1200)
    )
    XCTAssertEqual(
      LocalOcrPlugin.orientedSize(width: 1200, height: 800, orientation: .up),
      CGSize(width: 1200, height: 800)
    )
  }

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}
