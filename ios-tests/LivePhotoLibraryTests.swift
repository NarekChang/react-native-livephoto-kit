import XCTest
@testable import LivePhotoCore

final class LivePhotoLibraryTests: XCTestCase {
  override func tearDownWithError() throws {
    try LivePhotoFiles.clear()
  }

  /// The path `pickLivePhoto` takes after the system picker returns a PHLivePhoto.
  func testExportsTheResourcesOfALivePhoto() async throws {
    let pair = try await LivePhotoGenerator.generate(
      videoURL: Fixtures.video, photoURL: nil, keyPhotoTime: nil, maxDuration: nil
    )
    let livePhoto = await Inspect.livePhoto(pair.photoURL, pair.videoURL)

    let exported = try await LivePhotoLibrary.exportResources(of: try XCTUnwrap(livePhoto))

    XCTAssertNotEqual(exported.photoURL, pair.photoURL)
    XCTAssertEqual(try Data(contentsOf: exported.photoURL), try Data(contentsOf: pair.photoURL))
    XCTAssertEqual(try Data(contentsOf: exported.videoURL), try Data(contentsOf: pair.videoURL))
    let reloaded = await Inspect.livePhoto(exported.photoURL, exported.videoURL)
    XCTAssertNotNil(reloaded)
  }

  func testNamesAuthorizationStatuses() {
    XCTAssertEqual(LivePhotoLibrary.name(of: .notDetermined), "notDetermined")
    XCTAssertEqual(LivePhotoLibrary.name(of: .limited), "limited")
    XCTAssertEqual(LivePhotoLibrary.name(of: .authorized), "authorized")
  }
}
