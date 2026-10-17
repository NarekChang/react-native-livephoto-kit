// swift-tools-version:5.9

// Test harness only: the library ships through CocoaPods (RNLivePhoto.podspec), not SwiftPM.
// It compiles the UIKit-free part of ios/ for macOS so `swift test` can exercise the Live Photo
// generator against the real Photos framework without a simulator.
import PackageDescription

let package = Package(
  name: "RNLivePhotoTests",
  platforms: [.macOS(.v13)],
  targets: [
    .target(
      name: "LivePhotoCore",
      path: "ios",
      // UIKit and React glue; built only by CocoaPods.
      exclude: [
        "LivePhotoContentView.swift",
        "LivePhotoModule.swift",
        "LivePhotoPicker.swift",
        "RNLivePhotoModule.h",
        "RNLivePhotoModule.mm",
        "RNLivePhotoSwift.h",
        "RNLivePhotoView.h",
        "RNLivePhotoView.mm",
      ],
      sources: [
        "LivePhotoFiles.swift",
        "LivePhotoGenerator.swift",
        "LivePhotoLibrary.swift",
      ]
    ),
    .testTarget(
      name: "LivePhotoCoreTests",
      dependencies: ["LivePhotoCore"],
      path: "ios-tests"
    ),
  ]
)
