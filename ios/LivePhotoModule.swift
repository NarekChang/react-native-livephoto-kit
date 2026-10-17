import Foundation
import Photos
import UIKit

/// Swift side of the `LivePhoto` Turbo Module. `RNLivePhotoModule.mm` forwards the codegen spec methods here.
@objc(RNLivePhotoModuleImpl)
public final class LivePhotoModuleImpl: NSObject {
  public typealias Resolve = @Sendable (Any?) -> Void
  public typealias Reject = @Sendable (String, String) -> Void

  private static let generations = GenerationRegistry()

  /// `requestId` makes the generation cancellable with `cancelGenerate(requestId:)`.
  @objc(generateWithVideoUri:photoUri:keyPhotoTime:maxDuration:requestId:onProgress:resolve:reject:)
  public static func generate(
    videoUri: String,
    photoUri: String?,
    keyPhotoTime: NSNumber?,
    maxDuration: NSNumber?,
    requestId: String?,
    onProgress: (@Sendable (Double) -> Void)?,
    resolve: @escaping Resolve,
    reject: @escaping Reject
  ) {
    let task = run(resolve, reject) {
      defer {
        if let requestId { generations.finish(requestId) }
      }
      async let videoURL = LivePhotoFiles.localURL(for: videoUri)
      var photoURL: URL?
      if let photoUri {
        photoURL = try await LivePhotoFiles.localURL(for: photoUri)
      }
      let pair = try await LivePhotoGenerator.generate(
        videoURL: videoURL,
        photoURL: photoURL,
        keyPhotoTime: keyPhotoTime?.doubleValue,
        maxDuration: maxDuration?.doubleValue,
        progress: onProgress
      )
      return [
        "photoUri": pair.photoURL.absoluteString,
        "videoUri": pair.videoURL.absoluteString,
      ]
    }
    if let requestId {
      generations.register(requestId, task)
    }
  }

  /// The pending `generate` promise rejects with `E_CANCELLED`.
  @objc(cancelGenerateWithRequestId:)
  public static func cancelGenerate(requestId: String) {
    generations.cancel(requestId)
  }

  @objc(saveToLibraryWithPhotoUri:videoUri:resolve:reject:)
  public static func saveToLibrary(
    photoUri: String,
    videoUri: String,
    resolve: @escaping Resolve,
    reject: @escaping Reject
  ) {
    run(resolve, reject) {
      async let photoURL = LivePhotoFiles.localURL(for: photoUri)
      async let videoURL = LivePhotoFiles.localURL(for: videoUri)
      return try await LivePhotoLibrary.save(LivePhotoPair(photoURL: photoURL, videoURL: videoURL))
    }
  }

  @objc(requestPermissionWithAccessLevel:resolve:)
  public static func requestPermission(accessLevel: String, resolve: @escaping Resolve) {
    Task {
      let status = await LivePhotoLibrary.requestAuthorization(accessLevel == "readWrite" ? .readWrite : .addOnly)
      resolve(LivePhotoLibrary.name(of: status))
    }
  }

  /// Resolves with `null` when the user cancels.
  @objc(pickFrom:resolve:reject:)
  public static func pick(from presenter: UIViewController?, resolve: @escaping Resolve, reject: @escaping Reject) {
    Task { @MainActor in
      guard let presenter else {
        let error = LivePhotoError.loading("no view controller to present the picker from")
        reject(error.code, error.localizedDescription)
        return
      }
      do {
        guard let picked = try await LivePhotoPicker.pick(from: presenter) else {
          resolve(NSNull())
          return
        }
        var result: [String: Any] = [
          "photoUri": picked.pair.photoURL.absoluteString,
          "videoUri": picked.pair.videoURL.absoluteString,
        ]
        result["assetId"] = picked.assetId
        resolve(result)
      } catch {
        let error = LivePhotoError.wrap(error)
        reject(error.code, error.localizedDescription)
      }
    }
  }

  @objc(clearCacheWithResolve:reject:)
  public static func clearCache(resolve: @escaping Resolve, reject: @escaping Reject) {
    run(resolve, reject) {
      try LivePhotoFiles.clear()
      return NSNull()
    }
  }

  @discardableResult
  private static func run(
    _ resolve: @escaping Resolve,
    _ reject: @escaping Reject,
    _ work: @escaping @Sendable () async throws -> Any
  ) -> Task<Void, Never> {
    Task {
      do {
        resolve(try await work())
      } catch {
        let error = LivePhotoError.wrap(error)
        reject(error.code, error.localizedDescription)
      }
    }
  }
}

/// Running generations by request id. A generation can finish before it is registered,
/// so finished ids are remembered until their registration arrives.
private final class GenerationRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var tasks: [String: Task<Void, Never>] = [:]
  private var finished: Set<String> = []

  func register(_ requestId: String, _ task: Task<Void, Never>) {
    lock.lock()
    defer { lock.unlock() }
    if finished.remove(requestId) == nil {
      tasks[requestId] = task
    }
  }

  func finish(_ requestId: String) {
    lock.lock()
    defer { lock.unlock() }
    if tasks.removeValue(forKey: requestId) == nil {
      finished.insert(requestId)
    }
  }

  func cancel(_ requestId: String) {
    lock.lock()
    let task = tasks.removeValue(forKey: requestId)
    lock.unlock()
    task?.cancel()
  }
}
