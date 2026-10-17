import XCTest
@testable import LivePhotoCore

final class LivePhotoGeneratorTests: XCTestCase {
  override func setUpWithError() throws {
    try LivePhotoFiles.clear()
  }

  override func tearDownWithError() throws {
    try LivePhotoFiles.clear()
  }

  func testGeneratesAPairThatPhotosAccepts() async throws {
    let pair = try await LivePhotoGenerator.generate(
      videoURL: Fixtures.video, photoURL: nil, keyPhotoTime: nil, maxDuration: nil
    )

    let photoID = try XCTUnwrap(Inspect.photoIdentifier(pair.photoURL))
    let videoID = try await Inspect.videoIdentifier(pair.videoURL)
    XCTAssertEqual(photoID, videoID)
    XCTAssertEqual(Inspect.photoSize(pair.photoURL), CGSize(width: 720, height: 1280))
    let duration = try await Inspect.duration(pair.videoURL)
    XCTAssertEqual(duration, 3, accuracy: 0.01)
    let keyPhotoTime = try await Inspect.keyPhotoTime(pair.videoURL)
    XCTAssertEqual(try XCTUnwrap(keyPhotoTime), 1.5, accuracy: 0.01, "defaults to the middle")
    let livePhoto = await Inspect.livePhoto(pair.photoURL, pair.videoURL)
    XCTAssertNotNil(livePhoto)
  }

  func testUsesTheGivenKeyPhoto() async throws {
    let photo = try Fixtures.makePhoto(width: 64, height: 48)
    let pair = try await LivePhotoGenerator.generate(
      videoURL: Fixtures.video, photoURL: photo, keyPhotoTime: 0.5, maxDuration: nil
    )

    XCTAssertEqual(Inspect.photoSize(pair.photoURL), CGSize(width: 64, height: 48))
    XCTAssertNotNil(Inspect.photoIdentifier(pair.photoURL))
    let keyPhotoTime = try await Inspect.keyPhotoTime(pair.videoURL)
    XCTAssertEqual(try XCTUnwrap(keyPhotoTime), 0.5, accuracy: 0.01)
    let livePhoto = await Inspect.livePhoto(pair.photoURL, pair.videoURL)
    XCTAssertNotNil(livePhoto)
  }

  func testRejectsMismatchedFiles() async throws {
    let first = try await LivePhotoGenerator.generate(videoURL: Fixtures.video, photoURL: nil, keyPhotoTime: nil, maxDuration: nil)
    let second = try await LivePhotoGenerator.generate(videoURL: Fixtures.video, photoURL: nil, keyPhotoTime: nil, maxDuration: nil)
    let livePhoto = await Inspect.livePhoto(first.photoURL, second.videoURL)
    XCTAssertNil(livePhoto, "Photos must not pair files with different identifiers")
  }

  func testTrimsAroundTheKeyPhoto() async throws {
    // (keyPhotoTime, maxDuration) -> (duration, key photo time in the trimmed movie)
    let cases: [(Double?, Double, Double, Double)] = [
      (1.0, 1.5, 1.5, 0.75), // window centered on the key photo
      (2.9, 1.0, 1.0, 0.9), // window shifted to stay inside the video
      (0.1, 1.0, 1.0, 0.1), // ...and at the start
      (nil, 10, 3, 1.5), // longer than the video: untouched
    ]
    for (keyPhotoTime, maxDuration, expectedDuration, expectedKeyPhotoTime) in cases {
      let pair = try await LivePhotoGenerator.generate(
        videoURL: Fixtures.video, photoURL: nil, keyPhotoTime: keyPhotoTime, maxDuration: maxDuration
      )
      let label = "keyPhotoTime \(String(describing: keyPhotoTime)), maxDuration \(maxDuration)"
      let duration = try await Inspect.duration(pair.videoURL)
      XCTAssertEqual(duration, expectedDuration, accuracy: 0.02, label)
      let actualKeyPhotoTime = try await Inspect.keyPhotoTime(pair.videoURL)
      XCTAssertEqual(try XCTUnwrap(actualKeyPhotoTime), expectedKeyPhotoTime, accuracy: 0.02, label)
      let decodes = await Inspect.firstFrameDecodes(pair.videoURL)
      XCTAssertTrue(decodes, "trimmed movie must start decodable: \(label)")
      let livePhoto = await Inspect.livePhoto(pair.photoURL, pair.videoURL)
      XCTAssertNotNil(livePhoto, label)
    }
  }

  func testRejectsInvalidInput() async throws {
    await XCTAssertThrowsLivePhotoError("E_INVALID_INPUT") {
      try await LivePhotoGenerator.generate(videoURL: Fixtures.video, photoURL: nil, keyPhotoTime: nil, maxDuration: 0)
    }
    let notAnImage = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
    try Data("not an image".utf8).write(to: notAnImage)
    await XCTAssertThrowsLivePhotoError("E_INVALID_INPUT") {
      try await LivePhotoGenerator.generate(videoURL: Fixtures.video, photoURL: notAnImage, keyPhotoTime: nil, maxDuration: nil)
    }
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: LivePhotoFiles.directory.path)
    XCTAssertEqual(leftovers, [], "failed generations must not leave files behind")
  }

  func testReportsMonotonicProgressEndingAtOne() async throws {
    final class Values: @unchecked Sendable {
      let lock = NSLock()
      var all: [Double] = []
    }
    let values = Values()
    _ = try await LivePhotoGenerator.generate(
      videoURL: Fixtures.video, photoURL: nil, keyPhotoTime: nil, maxDuration: nil
    ) { progress in
      values.lock.lock()
      values.all.append(progress)
      values.lock.unlock()
    }

    let all = values.all
    XCTAssertGreaterThan(all.count, 5)
    XCTAssertEqual(all.last, 1)
    XCTAssertTrue(zip(all, all.dropFirst()).allSatisfy { $0 < $1 }, "\(all)")
    XCTAssertTrue(zip(all, all.dropFirst()).allSatisfy { $1 - $0 >= 0.01 || $1 == 1 }, "throttled to 1% steps")
  }

  func testCancellationStopsAndCleansUp() async throws {
    final class Holder: @unchecked Sendable {
      var task: Task<LivePhotoPair, Error>?
    }
    let holder = Holder()
    let task = Task {
      try await LivePhotoGenerator.generate(
        videoURL: Fixtures.video, photoURL: nil, keyPhotoTime: nil, maxDuration: nil
      ) { progress in
        if progress > 0.3 { holder.task?.cancel() }
      }
    }
    holder.task = task

    await XCTAssertThrowsLivePhotoError("E_CANCELLED") { try await task.value }
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: LivePhotoFiles.directory.path)
    XCTAssertEqual(leftovers, [])
  }
}
