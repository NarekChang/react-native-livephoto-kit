import CryptoKit
import Foundation

enum LivePhotoError: LocalizedError {
  case invalidUri(String)
  case invalidInput(String)
  case download(String, Error)
  case missingVideoTrack
  case unreadablePhoto
  case keyPhotoExtraction(Error)
  case writing(String)
  case notAuthorized
  case assetNotFound(String)
  case loading(String)
  case cancelled
  case unknown(Error)

  static func wrap(_ error: Error) -> LivePhotoError {
    if let error = error as? LivePhotoError {
      return error
    }
    if error is CancellationError || (error as? URLError)?.code == .cancelled {
      return .cancelled
    }
    return .unknown(error)
  }

  var errorDescription: String? {
    switch self {
    case .invalidUri(let uri): return "Invalid URI: \(uri)"
    case .invalidInput(let reason): return "Invalid input: \(reason)"
    case .download(let uri, let error): return "Failed to download \(uri): \(error.localizedDescription)"
    case .missingVideoTrack: return "The video has no video track"
    case .unreadablePhoto: return "Unable to read the photo"
    case .keyPhotoExtraction(let error): return "Unable to extract a key photo from the video: \(error.localizedDescription)"
    case .writing(let reason): return "Failed to write the Live Photo: \(reason)"
    case .notAuthorized: return "Photo library access is not authorized"
    case .assetNotFound(let id): return "No Photos asset with identifier \(id)"
    case .loading(let reason): return "Failed to load the Live Photo: \(reason)"
    case .cancelled: return "The operation was cancelled"
    case .unknown(let error): return error.localizedDescription
    }
  }

  var code: String {
    switch self {
    case .invalidUri: return "E_INVALID_URI"
    case .download: return "E_DOWNLOAD"
    case .invalidInput, .missingVideoTrack, .unreadablePhoto, .keyPhotoExtraction: return "E_INVALID_INPUT"
    case .writing: return "E_WRITE"
    case .notAuthorized: return "E_PERMISSION"
    case .assetNotFound: return "E_ASSET_NOT_FOUND"
    case .loading: return "E_LOAD"
    case .cancelled: return "E_CANCELLED"
    case .unknown: return "E_UNKNOWN"
    }
  }
}

enum LivePhotoFiles {
  /// Directory for generated and downloaded files. Lives in Caches so the system may purge it.
  static var directory: URL {
    get throws {
      let url = try baseURL
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      return url
    }
  }

  /// Deletes every file this library has generated or downloaded.
  static func clear() throws {
    let url = try baseURL
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private static var baseURL: URL {
    get throws {
      try FileManager.default
        .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appendingPathComponent("RNLivePhoto", isDirectory: true)
    }
  }

  static func makeURL(extension ext: String) throws -> URL {
    try directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
  }

  /// Turns a `file://` URI, a plain path or an `http(s)://` URI into a local file URL.
  /// Remote files are downloaded once into the cache directory and reused afterwards.
  static func localURL(for uri: String) async throws -> URL {
    if uri.hasPrefix("/") {
      return URL(fileURLWithPath: uri)
    }
    guard let url = URL(string: uri), let scheme = url.scheme?.lowercased() else {
      throw LivePhotoError.invalidUri(uri)
    }
    switch scheme {
    case "file":
      return url
    case "http", "https":
      return try await download(url)
    default:
      throw LivePhotoError.invalidUri(uri)
    }
  }

  private static func download(_ url: URL) async throws -> URL {
    let directory = try directory.appendingPathComponent("downloads", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // The extension may come from the response, so cached files are found by the hashed name alone.
    let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    if let cached = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .first(where: { $0.deletingPathExtension().lastPathComponent == name }) {
      return cached
    }

    do {
      let (tempURL, response) = try await URLSession.shared.download(from: url)
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw URLError(.badServerResponse)
      }
      // Keep the original extension: AVFoundation and ImageIO rely on it to detect the format.
      let ext = url.pathExtension.isEmpty ? (response.suggestedFilename as NSString?)?.pathExtension ?? "" : url.pathExtension
      let destination = directory.appendingPathComponent(name).appendingPathExtension(ext)
      do {
        try FileManager.default.moveItem(at: tempURL, to: destination)
      } catch where FileManager.default.fileExists(atPath: destination.path) {
        // A concurrent download of the same URL finished first.
      }
      return destination
    } catch {
      let wrapped = LivePhotoError.wrap(error)
      if case .unknown = wrapped {
        throw LivePhotoError.download(url.absoluteString, error)
      }
      throw wrapped
    }
  }
}
