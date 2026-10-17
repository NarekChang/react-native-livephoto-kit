import AVFoundation
import ImageIO
import Photos
import PhotosUI
import UniformTypeIdentifiers
import XCTest
@testable import LivePhotoCore

enum Fixtures {
  /// 3-second 720×1280 H.264 + AAC clip, shared with the example app.
  static let video = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("example/src/assets/sample.mov")

  /// Writes a solid-color PNG to a temporary file.
  static func makePhoto(width: Int = 64, height: Int = 48) throws -> URL {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url
  }
}

extension LivePhotoFiles {
  /// The cache directory without creating it, unlike `directory`.
  static var existingDirectory: URL? {
    let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("RNLivePhoto", isDirectory: true)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }
}

enum Inspect {
  /// The content identifier stored in the photo's Apple maker note.
  static func photoIdentifier(_ url: URL) -> String? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any] else {
      return nil
    }
    return makerApple["17"] as? String
  }

  static func photoSize(_ url: URL) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
      return nil
    }
    return CGSize(width: width, height: height)
  }

  /// The content identifier stored in the movie's QuickTime metadata.
  static func videoIdentifier(_ url: URL) async throws -> String? {
    let items = try await AVURLAsset(url: url).loadMetadata(for: .quickTimeMetadata)
    for item in items where item.identifier?.rawValue == "mdta/com.apple.quicktime.content.identifier" {
      return try await item.load(.stringValue)
    }
    return nil
  }

  static func duration(_ url: URL) async throws -> Double {
    try await AVURLAsset(url: url).load(.duration).seconds
  }

  /// Presentation time of the still-image-time marker, in the movie's timeline.
  static func keyPhotoTime(_ url: URL) async throws -> Double? {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .metadata).first else { return nil }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
    reader.add(output)
    reader.startReading()
    while let group = adaptor.nextTimedMetadataGroup() {
      if group.items.contains(where: { $0.identifier?.rawValue == "mdta/com.apple.quicktime.still-image-time" }) {
        return group.timeRange.start.seconds
      }
    }
    return nil
  }

  static func firstFrameDecodes(_ url: URL) async -> Bool {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return (try? await generator.image(at: .zero)) != nil
  }

  /// Asks Photos to pair the files. Returns nil when they are not a valid Live Photo.
  static func livePhoto(_ photo: URL, _ video: URL) async -> PHLivePhoto? {
    final class Once: @unchecked Sendable { var done = false }
    let once = Once()
    return await withCheckedContinuation { continuation in
      PHLivePhoto.request(
        withResourceFileURLs: [photo, video],
        placeholderImage: nil,
        targetSize: .zero,
        contentMode: .aspectFit
      ) { livePhoto, info in
        if once.done || (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true { return }
        once.done = true
        continuation.resume(returning: livePhoto)
      }
    }
  }
}

func XCTAssertThrowsLivePhotoError<T>(
  _ expectedCode: String,
  file: StaticString = #filePath,
  line: UInt = #line,
  _ body: () async throws -> T
) async {
  do {
    _ = try await body()
    XCTFail("expected \(expectedCode), but no error was thrown", file: file, line: line)
  } catch {
    XCTAssertEqual(LivePhotoError.wrap(error).code, expectedCode, "\(error)", file: file, line: line)
  }
}

/// Serves canned responses for https://stub.test/... through URLSession.shared.
final class StubURLProtocol: URLProtocol {
  private static let lock = NSLock()
  private static var responses: [String: (status: Int, data: Data)] = [:]
  private static var requests: [String] = []

  static func install() {
    URLProtocol.registerClass(StubURLProtocol.self)
  }

  static func uninstall() {
    URLProtocol.unregisterClass(StubURLProtocol.self)
    lock.lock()
    responses = [:]
    requests = []
    lock.unlock()
  }

  static func respond(to path: String, status: Int = 200, with data: Data) {
    lock.lock()
    responses[path] = (status, data)
    lock.unlock()
  }

  static func requestCount(for path: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    return requests.filter { $0 == path }.count
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "stub.test"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let url = request.url!
    Self.lock.lock()
    Self.requests.append(url.path)
    let response = Self.responses[url.path] ?? (404, Data())
    Self.lock.unlock()

    let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: nil)!
    client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: response.data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
