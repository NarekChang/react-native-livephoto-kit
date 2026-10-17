@preconcurrency import Photos
@preconcurrency import PhotosUI
import UIKit

struct PickedLivePhoto {
  let pair: LivePhotoPair
  let assetId: String?
}

/// Presents `PHPickerViewController` limited to Live Photos. The picker runs out of process,
/// so no photo library permission is needed.
@MainActor
final class LivePhotoPicker: NSObject, PHPickerViewControllerDelegate {
  private static var current: LivePhotoPicker?
  private var continuation: CheckedContinuation<PHPickerResult?, Never>?

  /// Returns nil when the user cancels.
  static func pick(from presenter: UIViewController) async throws -> PickedLivePhoto? {
    guard current == nil else {
      throw LivePhotoError.invalidInput("a Live Photo picker is already presented")
    }
    // Passing the shared library makes the picker return asset identifiers.
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .livePhotos
    configuration.selectionLimit = 1
    configuration.preferredAssetRepresentationMode = .current

    let handler = LivePhotoPicker()
    current = handler
    defer { current = nil }

    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = handler
    let selection = await withCheckedContinuation { continuation in
      handler.continuation = continuation
      presenter.present(picker, animated: true)
    }
    guard let selection else { return nil }

    let livePhoto = try await loadLivePhoto(from: selection.itemProvider)
    let pair = try await LivePhotoLibrary.exportResources(of: livePhoto)
    return PickedLivePhoto(pair: pair, assetId: selection.assetIdentifier)
  }

  // Called on the main thread, also when the sheet is swiped away (with no results).
  nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    DispatchQueue.main.async {
      picker.dismiss(animated: true)
      self.continuation?.resume(returning: results.first)
      self.continuation = nil
    }
  }

  private static func loadLivePhoto(from provider: NSItemProvider) async throws -> PHLivePhoto {
    guard provider.canLoadObject(ofClass: PHLivePhoto.self) else {
      throw LivePhotoError.loading("the selected item is not a Live Photo")
    }
    return try await withCheckedThrowingContinuation { continuation in
      provider.loadObject(ofClass: PHLivePhoto.self) { object, error in
        if let livePhoto = object as? PHLivePhoto {
          continuation.resume(returning: livePhoto)
        } else {
          continuation.resume(throwing: LivePhotoError.loading(error?.localizedDescription ?? "unable to load the Live Photo"))
        }
      }
    }
  }
}
