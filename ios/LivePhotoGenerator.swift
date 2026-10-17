@preconcurrency import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct LivePhotoPair {
  let photoURL: URL
  let videoURL: URL
}

/// Builds a Live Photo resource pair: a JPEG and a QuickTime movie that share a content identifier.
///
/// Photos pairs the two files by that identifier, which lives in
/// - the photo's Apple maker note (key "17"), and
/// - the movie's `com.apple.quicktime.content.identifier` metadata.
/// The movie also needs a timed `still-image-time` metadata track marking the frame shown as the key photo.
enum LivePhotoGenerator {
  private static let contentIdentifierKey = "com.apple.quicktime.content.identifier"
  private static let stillImageTimeKey = "com.apple.quicktime.still-image-time"
  private static let makerAppleContentIdentifierKey = "17"

  /// - Parameters:
  ///   - maxDuration: When the video is longer, only a window of this length around the key photo is kept.
  ///   - progress: Called with values from 0 to 1, on a background queue.
  static func generate(
    videoURL: URL,
    photoURL: URL?,
    keyPhotoTime: Double?,
    maxDuration: Double?,
    progress: LivePhotoProgress? = nil
  ) async throws -> LivePhotoPair {
    let reporter = ProgressReporter(progress)
    if let maxDuration, !(maxDuration > 0) {
      throw LivePhotoError.invalidInput("maxDuration must be greater than 0")
    }
    let asset = AVURLAsset(url: videoURL)
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
      throw LivePhotoError.missingVideoTrack
    }
    let duration = try await asset.load(.duration)
    let keyPhoto = clampedKeyPhotoTime(keyPhotoTime, duration: duration)
    let timeRange = trimmedTimeRange(duration: duration, around: keyPhoto, maxDuration: maxDuration)
    let identifier = UUID().uuidString

    let pair = LivePhotoPair(
      photoURL: try LivePhotoFiles.makeURL(extension: "jpg"),
      videoURL: try LivePhotoFiles.makeURL(extension: "mov")
    )

    do {
      if let photoURL {
        try writePhoto(from: photoURL, identifier: identifier, to: pair.photoURL)
      } else {
        let image = try await keyFrame(of: asset, at: keyPhoto)
        try writePhoto(image, identifier: identifier, to: pair.photoURL)
      }
      try Task.checkCancellation()
      reporter.report(photoShare)
      try await writeVideo(
        asset: asset,
        videoTrack: videoTrack,
        timeRange: timeRange,
        identifier: identifier,
        keyPhotoTime: keyPhoto,
        to: pair.videoURL
      ) { position in
        // Passthrough reading may start at the keyframe before the range; clamp to 0.
        let fraction = (position - timeRange.start).seconds / timeRange.duration.seconds
        reporter.report(photoShare + (1 - photoShare) * min(max(fraction, 0), 1))
      }
    } catch {
      try? FileManager.default.removeItem(at: pair.photoURL)
      try? FileManager.default.removeItem(at: pair.videoURL)
      throw error
    }
    reporter.report(1)
    return pair
  }

  /// Share of the progress given to the key photo; copying the video takes the rest.
  private static let photoShare = 0.05

  private static func clampedKeyPhotoTime(_ seconds: Double?, duration: CMTime) -> CMTime {
    let total = duration.seconds
    guard total.isFinite, total > 0 else { return .zero }
    let requested = seconds ?? total / 2
    return CMTime(seconds: min(max(requested, 0), total), preferredTimescale: duration.timescale)
  }

  private static func trimmedTimeRange(duration: CMTime, around keyPhoto: CMTime, maxDuration: Double?) -> CMTimeRange {
    let total = duration.seconds
    guard let maxDuration, total.isFinite, maxDuration < total else {
      return CMTimeRange(start: .zero, duration: duration)
    }
    // Center the window on the key photo, shifting it to stay inside the video.
    let start = min(max(keyPhoto.seconds - maxDuration / 2, 0), total - maxDuration)
    return CMTimeRange(
      start: CMTime(seconds: start, preferredTimescale: duration.timescale),
      duration: CMTime(seconds: maxDuration, preferredTimescale: duration.timescale)
    )
  }

  // MARK: - Photo

  private static func keyFrame(of asset: AVAsset, at time: CMTime) async throws -> CGImage {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    do {
      if #available(iOS 16.0, *) {
        return try await generator.image(at: time).image
      }
      return try generator.copyCGImage(at: time, actualTime: nil)
    } catch {
      throw LivePhotoError.keyPhotoExtraction(error)
    }
  }

  private static func writePhoto(from sourceURL: URL, identifier: String, to url: URL) throws {
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
      throw LivePhotoError.unreadablePhoto
    }
    let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    var makerApple = sourceProperties?[kCGImagePropertyMakerAppleDictionary] as? [String: Any] ?? [:]
    makerApple[makerAppleContentIdentifierKey] = identifier

    let destination = try makeDestination(url)
    // Copies the image together with its original metadata (orientation, EXIF, GPS) and merges the maker note.
    CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImagePropertyMakerAppleDictionary: makerApple] as CFDictionary)
    try finalize(destination)
  }

  private static func writePhoto(_ image: CGImage, identifier: String, to url: URL) throws {
    let destination = try makeDestination(url)
    let properties: [CFString: Any] = [
      kCGImagePropertyMakerAppleDictionary: [makerAppleContentIdentifierKey: identifier],
      kCGImageDestinationLossyCompressionQuality: 0.9,
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    try finalize(destination)
  }

  private static func makeDestination(_ url: URL) throws -> CGImageDestination {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
      throw LivePhotoError.writing("cannot create the photo file")
    }
    return destination
  }

  private static func finalize(_ destination: CGImageDestination) throws {
    guard CGImageDestinationFinalize(destination) else {
      throw LivePhotoError.writing("cannot encode the photo")
    }
  }

  // MARK: - Video

  private static func writeVideo(
    asset: AVAsset,
    videoTrack: AVAssetTrack,
    timeRange: CMTimeRange,
    identifier: String,
    keyPhotoTime: CMTime,
    to url: URL,
    onVideoSample: @escaping @Sendable (CMTime) -> Void
  ) async throws {
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = timeRange
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    writer.metadata = [metadataItem(key: contentIdentifierKey, value: identifier as NSString, dataType: kCMMetadataBaseDataType_UTF8)]

    // Samples are copied as-is (passthrough): no re-encoding, original codec and quality are kept.
    var tracks = [videoTrack]
    if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
      tracks.append(audioTrack)
    }
    var pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
    for track in tracks {
      let (formats, transform) = try await track.load(.formatDescriptions, .preferredTransform)
      let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
      output.alwaysCopiesSampleData = false
      let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: formats.first)
      input.expectsMediaDataInRealTime = false
      input.transform = transform
      guard reader.canAdd(output), writer.canAdd(input) else {
        throw LivePhotoError.writing("unsupported \(track.mediaType.rawValue) track")
      }
      reader.add(output)
      writer.add(input)
      pairs.append((output, input))
    }

    let metadataInput = try makeStillImageTimeInput()
    guard writer.canAdd(metadataInput) else {
      throw LivePhotoError.writing("cannot add the still image time track")
    }
    let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
    writer.add(metadataInput)

    guard writer.startWriting() else {
      throw LivePhotoError.writing(writer.error?.localizedDescription ?? "cannot start writing")
    }
    guard reader.startReading() else {
      writer.cancelWriting()
      throw LivePhotoError.writing(reader.error?.localizedDescription ?? "cannot read the video")
    }
    // Passthrough reading starts at the preceding sync sample; the session start trims the movie
    // to the requested range via an edit list, so the result is still decodable.
    writer.startSession(atSourceTime: timeRange.start)

    let frameRate = try await videoTrack.load(.nominalFrameRate)
    let frameDuration = CMTime(seconds: 1 / Double(frameRate > 0 ? frameRate : 30), preferredTimescale: 600)
    let stillImageTime = metadataItem(key: stillImageTimeKey, value: 0 as NSNumber, dataType: kCMMetadataBaseDataType_SInt8)
    metadataAdaptor.append(AVTimedMetadataGroup(items: [stillImageTime], timeRange: CMTimeRange(start: keyPhotoTime, duration: frameDuration)))
    metadataInput.markAsFinished()

    // The copy loops poll this flag. Calling reader.cancelReading() from the cancellation
    // handler instead would race with copyNextSampleBuffer() on the writer queues and crash.
    let cancellation = CancellationFlag()
    await withTaskCancellationHandler {
      await withTaskGroup(of: Void.self) { group in
        for (output, input) in pairs {
          let onSample = input.mediaType == .video ? onVideoSample : nil
          group.addTask {
            await copySamples(from: output, to: input, isCancelled: { cancellation.isSet() }, onSample: onSample)
          }
        }
      }
    } onCancel: {
      cancellation.set()
    }

    if cancellation.isSet() {
      reader.cancelReading()
      writer.cancelWriting()
      throw LivePhotoError.cancelled
    }

    if reader.status == .failed || writer.status == .failed {
      reader.cancelReading()
      writer.cancelWriting()
      throw LivePhotoError.writing((writer.error ?? reader.error)?.localizedDescription ?? "unknown error")
    }
    writer.endSession(atSourceTime: timeRange.end)
    await writer.finishWriting()
    guard writer.status == .completed else {
      throw LivePhotoError.writing(writer.error?.localizedDescription ?? "unknown error")
    }
  }

  private static func copySamples(
    from output: AVAssetReaderOutput,
    to input: AVAssetWriterInput,
    isCancelled: @escaping @Sendable () -> Bool,
    onSample: (@Sendable (CMTime) -> Void)?
  ) async {
    let queue = DispatchQueue(label: "react-native-livephoto.writer.\(input.mediaType.rawValue)")
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      input.requestMediaDataWhenReady(on: queue) {
        while input.isReadyForMoreMediaData {
          guard !isCancelled(), let buffer = output.copyNextSampleBuffer(), input.append(buffer) else {
            input.markAsFinished()
            continuation.resume()
            return
          }
          onSample?(CMSampleBufferGetPresentationTimeStamp(buffer))
        }
      }
    }
  }

  private static func makeStillImageTimeInput() throws -> AVAssetWriterInput {
    let specification: [CFString: Any] = [
      kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier: "\(AVMetadataKeySpace.quickTimeMetadata.rawValue)/\(stillImageTimeKey)",
      kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType: kCMMetadataBaseDataType_SInt8,
    ]
    var description: CMFormatDescription?
    let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
      allocator: kCFAllocatorDefault,
      metadataType: kCMMetadataFormatType_Boxed,
      metadataSpecifications: [specification] as CFArray,
      formatDescriptionOut: &description
    )
    guard status == noErr, let description else {
      throw LivePhotoError.writing("cannot describe the still image time track (\(status))")
    }
    return AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
  }

  private static func metadataItem(key: String, value: NSCopying & NSObjectProtocol, dataType: CFString) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.keySpace = .quickTimeMetadata
    item.key = key as NSString
    item.value = value
    item.dataType = dataType as String
    return item
  }
}

typealias LivePhotoProgress = @Sendable (Double) -> Void

/// Clamps, keeps monotonic and throttles progress to 1% steps so the bridge isn't flooded.
final class ProgressReporter: @unchecked Sendable {
  private let handler: LivePhotoProgress?
  private let lock = NSLock()
  private var last = -1.0

  init(_ handler: LivePhotoProgress?) {
    self.handler = handler
  }

  func report(_ value: Double) {
    guard let handler else { return }
    let value = min(max(value, 0), 1)
    lock.lock()
    let shouldReport = value > last && (value >= 1 || value - last >= 0.01)
    if shouldReport {
      last = value
    }
    lock.unlock()
    if shouldReport {
      handler(value)
    }
  }
}

final class CancellationFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  func set() {
    lock.lock()
    value = true
    lock.unlock()
  }

  func isSet() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}
