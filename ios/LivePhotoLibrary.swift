import Photos
import UniformTypeIdentifiers

enum LivePhotoLibrary {
  static func requestAuthorization(_ level: PHAccessLevel) async -> PHAuthorizationStatus {
    await PHPhotoLibrary.requestAuthorization(for: level)
  }

  /// Saves the pair as a single Live Photo asset and returns its local identifier.
  static func save(_ pair: LivePhotoPair) async throws -> String {
    let status = await requestAuthorization(.addOnly)
    guard status == .authorized || status == .limited else {
      throw LivePhotoError.notAuthorized
    }
    let result = PlaceholderBox()
    try await PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      request.addResource(with: .photo, fileURL: pair.photoURL, options: nil)
      request.addResource(with: .pairedVideo, fileURL: pair.videoURL, options: nil)
      result.placeholder = request.placeholderForCreatedAsset
    }
    return result.placeholder?.localIdentifier ?? ""
  }

  /// Writes the photo and paired video of a Live Photo (e.g. one returned by the system picker)
  /// into the cache directory. Doesn't require photo library access.
  static func exportResources(of livePhoto: PHLivePhoto) async throws -> LivePhotoPair {
    let resources = PHAssetResource.assetResources(for: livePhoto)
    guard let photo = resources.first(where: { $0.type == .photo }),
          let video = resources.first(where: { $0.type == .pairedVideo }) else {
      throw LivePhotoError.loading("the Live Photo has no photo or paired video resource")
    }
    let pair = LivePhotoPair(
      photoURL: try LivePhotoFiles.makeURL(extension: fileExtension(of: photo, fallback: "jpg")),
      videoURL: try LivePhotoFiles.makeURL(extension: fileExtension(of: video, fallback: "mov"))
    )
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = true
    do {
      try await PHAssetResourceManager.default().writeData(for: photo, toFile: pair.photoURL, options: options)
      try await PHAssetResourceManager.default().writeData(for: video, toFile: pair.videoURL, options: options)
    } catch {
      try? FileManager.default.removeItem(at: pair.photoURL)
      try? FileManager.default.removeItem(at: pair.videoURL)
      throw LivePhotoError.loading(error.localizedDescription)
    }
    return pair
  }

  private static func fileExtension(of resource: PHAssetResource, fallback: String) -> String {
    UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension ?? fallback
  }

  static func name(of status: PHAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorized: return "authorized"
    case .limited: return "limited"
    @unknown default: return "denied"
    }
  }

  private final class PlaceholderBox: @unchecked Sendable {
    var placeholder: PHObjectPlaceholder?
  }
}
