import Flutter
import ImageIO
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ImageDateNative") {
      ImageDateNative.register(with: registrar)
    }
  }
}

/// Native helpers for Image Date (channel "imagedate/native"):
/// - pickFolder: Files folder picker; returns the path and a bookmark so the
///   folder opens again in later app runs without a copy of the images.
/// - resolveBookmark: opens a folder again from its bookmark.
/// - downloadICloud: asks iCloud Drive to download files not on the device.
/// - decodeImage: decodes HEIC/AVIF/TIFF/DNG (any ImageIO format) to JPEG.
/// - imageInfo: pixel size from the file header.
final class ImageDateNative: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var pendingPick: FlutterResult?
  /// Folders with an active security scope for this app run.
  private var scoped: [String: URL] = [:]
  private let work = DispatchQueue(label: "imagedate.decode", qos: .userInitiated, attributes: .concurrent)

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "imagedate/native", binaryMessenger: registrar.messenger())
    let instance = ImageDateNative()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "pickFolder":
      pickFolder(result)
    case "resolveBookmark":
      resolveBookmark(args, result)
    case "downloadICloud":
      let paths = args["paths"] as? [String] ?? []
      for p in paths {
        try? FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: p))
      }
      result(nil)
    case "decodeImage":
      decodeImage(args, result)
    case "imageInfo":
      imageInfo(args, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Folder picker

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    var vc = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = vc?.presentedViewController {
      vc = presented
    }
    return vc
  }

  private func pickFolder(_ result: @escaping FlutterResult) {
    if pendingPick != nil {
      result(FlutterError(code: "busy", message: "A picker is already open", details: nil))
      return
    }
    guard let vc = topViewController() else {
      result(FlutterError(code: "no_window", message: "No window to show the picker", details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pendingPick = result
    vc.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pendingPick else { return }
    pendingPick = nil
    guard let url = urls.first else {
      result(nil)
      return
    }
    if url.startAccessingSecurityScopedResource() {
      scoped[url.path] = url
    }
    do {
      let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      result(["path": url.path, "name": url.lastPathComponent, "bookmark": data.base64EncodedString()])
    } catch {
      result(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingPick?(nil)
    pendingPick = nil
  }

  private func resolveBookmark(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let b64 = args["bookmark"] as? String, let data = Data(base64Encoded: b64) else {
      result(FlutterError(code: "bad_args", message: "Missing bookmark", details: nil))
      return
    }
    do {
      var stale = false
      let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
      if scoped[url.path] == nil, url.startAccessingSecurityScopedResource() {
        scoped[url.path] = url
      }
      var out: [String: Any] = ["path": url.path, "name": url.lastPathComponent]
      if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
        out["bookmark"] = fresh.base64EncodedString()
      }
      guard FileManager.default.fileExists(atPath: url.path) else {
        result(FlutterError(code: "not_found", message: "The folder is not available", details: nil))
        return
      }
      result(out)
    } catch {
      result(FlutterError(code: "resolve_failed", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: Images

  private func decodeImage(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let path = args["path"] as? String else {
      result(FlutterError(code: "bad_args", message: "Missing path", details: nil))
      return
    }
    let maxPixel = args["maxPixel"] as? Int ?? 0
    work.async {
      let url = URL(fileURLWithPath: path) as CFURL
      var opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
      ]
      if maxPixel > 0 {
        opts[kCGImageSourceThumbnailMaxPixelSize] = maxPixel
      }
      guard let source = CGImageSourceCreateWithURL(url, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary),
            let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.92)
      else {
        DispatchQueue.main.async {
          result(FlutterError(code: "decode_failed", message: "Cannot decode \(path)", details: nil))
        }
        return
      }
      DispatchQueue.main.async {
        result(FlutterStandardTypedData(bytes: data))
      }
    }
  }

  private func imageInfo(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let path = args["path"] as? String else {
      result(nil)
      return
    }
    work.async {
      var out: [String: Any]?
      if let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
         let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
         let w = props[kCGImagePropertyPixelWidth] as? Int,
         let h = props[kCGImagePropertyPixelHeight] as? Int {
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let swap = orientation >= 5 && orientation <= 8
        out = ["width": swap ? h : w, "height": swap ? w : h]
      }
      DispatchQueue.main.async {
        result(out)
      }
    }
  }
}
