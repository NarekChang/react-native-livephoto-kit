import XCTest
@testable import LivePhotoCore

final class LivePhotoFilesTests: XCTestCase {
  override func setUpWithError() throws {
    try LivePhotoFiles.clear()
    StubURLProtocol.install()
  }

  override func tearDownWithError() throws {
    StubURLProtocol.uninstall()
    try LivePhotoFiles.clear()
  }

  func testResolvesLocalURIs() async throws {
    let path = Fixtures.video.path
    let fromPath = try await LivePhotoFiles.localURL(for: path)
    let fromFileURI = try await LivePhotoFiles.localURL(for: Fixtures.video.absoluteString)
    XCTAssertEqual(fromPath.path, path)
    XCTAssertEqual(fromFileURI.path, path)
  }

  func testRejectsUnsupportedURIs() async {
    for uri in ["relative/path.mov", "ftp://example.com/a.mov", "ph://ABC"] {
      await XCTAssertThrowsLivePhotoError("E_INVALID_URI") {
        try await LivePhotoFiles.localURL(for: uri)
      }
    }
  }

  func testDownloadsOnceAndReusesTheFile() async throws {
    let data = try Data(contentsOf: Fixtures.video)
    StubURLProtocol.respond(to: "/clip.mov", with: data)

    let first = try await LivePhotoFiles.localURL(for: "https://stub.test/clip.mov")
    let second = try await LivePhotoFiles.localURL(for: "https://stub.test/clip.mov")

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.pathExtension, "mov", "keeps the extension for AVFoundation")
    XCTAssertEqual(try Data(contentsOf: first), data)
    XCTAssertEqual(StubURLProtocol.requestCount(for: "/clip.mov"), 1)
  }

  func testDifferentURLsAreCachedSeparately() async throws {
    StubURLProtocol.respond(to: "/a.jpg", with: Data("a".utf8))
    let v1 = try await LivePhotoFiles.localURL(for: "https://stub.test/a.jpg?v=1")
    let v2 = try await LivePhotoFiles.localURL(for: "https://stub.test/a.jpg?v=2")
    XCTAssertNotEqual(v1, v2)
    XCTAssertEqual(StubURLProtocol.requestCount(for: "/a.jpg"), 2)
  }

  func testHTTPErrorsAreDownloadErrors() async throws {
    await XCTAssertThrowsLivePhotoError("E_DOWNLOAD") {
      try await LivePhotoFiles.localURL(for: "https://stub.test/missing.mov")
    }
    let downloads = LivePhotoFiles.existingDirectory?.appendingPathComponent("downloads")
    let files = downloads.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
    XCTAssertEqual(files, [], "failed downloads are not cached")
  }

  func testClearRemovesEverything() async throws {
    StubURLProtocol.respond(to: "/clip.mov", with: Data("x".utf8))
    _ = try await LivePhotoFiles.localURL(for: "https://stub.test/clip.mov")
    _ = try LivePhotoFiles.makeURL(extension: "jpg")

    try LivePhotoFiles.clear()
    try LivePhotoFiles.clear() // idempotent

    XCTAssertNil(LivePhotoFiles.existingDirectory)
    _ = try await LivePhotoFiles.localURL(for: "https://stub.test/clip.mov")
    XCTAssertEqual(StubURLProtocol.requestCount(for: "/clip.mov"), 2, "cleared files are downloaded again")
  }
}
