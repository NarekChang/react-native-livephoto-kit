import Photos
import PhotosUI
import UIKit

/// UIKit implementation of `<LivePhotoView>`. The Fabric component view (`RNLivePhotoView.mm`) owns it
/// and forwards props, commands and events.
@objc(RNLivePhotoContentView)
public final class LivePhotoContentView: UIView {
  @objc public var onLoad: ((CGSize) -> Void)?
  /// (code, message); codes match the promise rejection codes of the module.
  @objc public var onError: ((String, String) -> Void)?
  @objc public var onPlaybackStart: ((String) -> Void)?
  @objc public var onPlaybackEnd: ((String) -> Void)?

  /// "off", "hint" or "full".
  @objc public var autoplay = "off"
  @objc public var muted = false {
    didSet { livePhotoView.isMuted = muted }
  }
  @objc public var resizeMode = "cover" {
    didSet {
      let mode: UIView.ContentMode = resizeMode == "contain" ? .scaleAspectFit : .scaleAspectFill
      livePhotoView.contentMode = mode
      placeholderView.contentMode = mode
    }
  }
  /// URI of an image shown until the Live Photo is loaded; empty for none.
  @objc public var placeholder = "" {
    didSet { loadPlaceholder() }
  }
  @objc public var showsBadge = false {
    didSet { updateOverlays() }
  }
  /// Whether a long press plays the Live Photo.
  @objc public var gestureEnabled = true {
    didSet { livePhotoView.playbackGestureRecognizer.isEnabled = gestureEnabled }
  }

  private let livePhotoView = PHLivePhotoView()
  private let placeholderView = UIImageView()
  private let badgeView = UIImageView(image: PHLivePhotoView.livePhotoBadgeImage(options: .overContent))
  private lazy var delegate = PlaybackDelegate(owner: self)
  private var loadTask: Task<Void, Never>?
  private var placeholderTask: Task<Void, Never>?
  private var fileRequestID: PHLivePhotoRequestID?
  private var assetRequestID: PHImageRequestID?

  override public init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    livePhotoView.frame = bounds
    livePhotoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    livePhotoView.contentMode = .scaleAspectFill
    livePhotoView.delegate = delegate
    addSubview(livePhotoView)

    placeholderView.frame = bounds
    placeholderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    placeholderView.contentMode = .scaleAspectFill
    placeholderView.clipsToBounds = true
    addSubview(placeholderView)

    badgeView.isHidden = true
    addSubview(badgeView)
  }

  override public func layoutSubviews() {
    super.layoutSubviews()
    // Same inset as the badge in the Photos app.
    badgeView.frame.origin = CGPoint(x: 8, y: 8)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    loadTask?.cancel()
    placeholderTask?.cancel()
  }

  /// Empty strings mean "not set". `assetId` takes precedence over the file pair.
  @objc(setSourcePhotoUri:videoUri:assetId:)
  public func setSource(photoUri: String, videoUri: String, assetId: String) {
    cancelLoading()
    livePhotoView.stopPlayback()
    livePhotoView.livePhoto = nil
    updateOverlays()

    if !assetId.isEmpty {
      loadAsset(assetId)
    } else if !photoUri.isEmpty, !videoUri.isEmpty {
      loadFiles(photoUri: photoUri, videoUri: videoUri)
    } else if !photoUri.isEmpty || !videoUri.isEmpty {
      fail(.invalidInput("source requires both photoUri and videoUri"))
    }
  }

  @objc public func play(_ style: String) {
    livePhotoView.startPlayback(with: Self.playbackStyle(named: style))
  }

  @objc public func stop() {
    livePhotoView.stopPlayback()
  }

  // MARK: - Loading

  private func loadFiles(photoUri: String, videoUri: String) {
    loadTask = Task { [weak self] in
      do {
        async let photoURL = LivePhotoFiles.localURL(for: photoUri)
        async let videoURL = LivePhotoFiles.localURL(for: videoUri)
        let urls = try await [photoURL, videoURL]
        guard let self, !Task.isCancelled else { return }
        self.fileRequestID = PHLivePhoto.request(
          withResourceFileURLs: urls,
          placeholderImage: nil,
          targetSize: .zero,
          contentMode: .aspectFit
        ) { [weak self] livePhoto, info in
          DispatchQueue.main.async { self?.handle(livePhoto, info: info) }
        }
      } catch {
        guard !Task.isCancelled else { return }
        self?.fail(LivePhotoError.wrap(error))
      }
    }
  }

  private func loadAsset(_ assetId: String) {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
      fail(.assetNotFound(assetId))
      return
    }
    let options = PHLivePhotoRequestOptions()
    options.deliveryMode = .highQualityFormat
    options.isNetworkAccessAllowed = true
    assetRequestID = PHImageManager.default().requestLivePhoto(
      for: asset,
      targetSize: PHImageManagerMaximumSize,
      contentMode: .aspectFit,
      options: options
    ) { [weak self] livePhoto, info in
      DispatchQueue.main.async { self?.handle(livePhoto, info: info ?? [:]) }
    }
  }

  private func handle(_ livePhoto: PHLivePhoto?, info: [AnyHashable: Any]) {
    if (info[PHLivePhotoInfoCancelledKey] as? Bool) == true || (info[PHImageCancelledKey] as? Bool) == true {
      return
    }
    if let error = (info[PHLivePhotoInfoErrorKey] ?? info[PHImageErrorKey]) as? Error {
      fail(.loading(error.localizedDescription))
      return
    }
    let isDegraded = (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true || (info[PHImageResultIsDegradedKey] as? Bool) == true
    guard let livePhoto else {
      if !isDegraded {
        fail(.loading("the files are not a valid Live Photo pair"))
      }
      return
    }
    livePhotoView.livePhoto = livePhoto
    updateOverlays()
    guard !isDegraded else { return }

    onLoad?(livePhoto.size)
    if autoplay != "off" {
      play(autoplay)
    }
  }

  private func fail(_ error: LivePhotoError) {
    onError?(error.code, error.localizedDescription)
  }

  private func loadPlaceholder() {
    placeholderTask?.cancel()
    placeholderView.image = nil
    let uri = placeholder
    guard !uri.isEmpty else { return }
    placeholderTask = Task { [weak self] in
      do {
        let url = try await LivePhotoFiles.localURL(for: uri)
        let image = await Task.detached { UIImage(contentsOfFile: url.path) }.value
        guard let self, !Task.isCancelled, self.placeholder == uri else { return }
        self.placeholderView.image = image
      } catch {
        // A missing placeholder is not worth an onError: the Live Photo itself may still load.
      }
    }
  }

  /// The placeholder covers the view until a Live Photo is shown; the badge marks a shown one.
  private func updateOverlays() {
    let hasLivePhoto = livePhotoView.livePhoto != nil
    placeholderView.isHidden = hasLivePhoto
    badgeView.isHidden = !(showsBadge && hasLivePhoto)
  }

  private func cancelLoading() {
    loadTask?.cancel()
    loadTask = nil
    if let fileRequestID {
      PHLivePhoto.cancelRequest(withRequestID: fileRequestID)
      self.fileRequestID = nil
    }
    if let assetRequestID {
      PHImageManager.default().cancelImageRequest(assetRequestID)
      self.assetRequestID = nil
    }
  }

  // MARK: - Playback

  private static func playbackStyle(named name: String) -> PHLivePhotoViewPlaybackStyle {
    name == "full" ? .full : .hint
  }

  fileprivate nonisolated static func name(of style: PHLivePhotoViewPlaybackStyle) -> String {
    style == .full ? "full" : "hint"
  }

  /// Kept separate so the delegate conformance doesn't leak into the generated Objective-C header.
  private final class PlaybackDelegate: NSObject, PHLivePhotoViewDelegate {
    weak var owner: LivePhotoContentView?

    init(owner: LivePhotoContentView) {
      self.owner = owner
    }

    func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
      let style = LivePhotoContentView.name(of: playbackStyle)
      DispatchQueue.main.async { [weak owner] in owner?.onPlaybackStart?(style) }
    }

    func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
      let style = LivePhotoContentView.name(of: playbackStyle)
      DispatchQueue.main.async { [weak owner] in owner?.onPlaybackEnd?(style) }
    }
  }
}
