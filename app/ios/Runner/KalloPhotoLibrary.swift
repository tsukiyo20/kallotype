import Flutter
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// The Kallo album in Photos.
///
/// iOS owns the pictures. This bridge owns only the album membership and the
/// bytes: it creates `Kallo`, saves a marked PNG/JPEG as an asset in it, lists
/// its assets, and materialises one when the catalog needs to read a marker.
/// Nothing here decodes a picture to draw a wall; thumbnails are requested at
/// the size the wall asks for.
final class KalloPhotoLibrary: NSObject {
  static let channelName = "com.kallo.app/library"
  private static let albumTitle = "Kallo"

  private let channel: FlutterMethodChannel
  private var pickerDelegate: KalloPickerDelegate?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "the photo library bridge is gone", details: nil))
        return
      }
      self.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "open":
      open(result: result)
    case "list":
      list(result: result)
    case "save":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            let name = args["name"] as? String else {
        result(FlutterError(code: "bad_arguments", message: "save needs a path and a name", details: nil))
        return
      }
      save(path: path, name: name, result: result)
    case "materialize":
      guard let args = call.arguments as? [String: Any],
            let locator = args["locator"] as? String else {
        result(FlutterError(code: "bad_arguments", message: "materialize needs a locator", details: nil))
        return
      }
      materialize(locator: locator, result: result)
    case "thumbnail":
      guard let args = call.arguments as? [String: Any],
            let locator = args["locator"] as? String else {
        result(FlutterError(code: "bad_arguments", message: "thumbnail needs a locator", details: nil))
        return
      }
      image(locator: locator, width: (args["width"] as? NSNumber)?.intValue ?? 512, result: result)
    case "image":
      guard let args = call.arguments as? [String: Any],
            let locator = args["locator"] as? String else {
        result(FlutterError(code: "bad_arguments", message: "image needs a locator", details: nil))
        return
      }
      image(locator: locator, width: (args["width"] as? NSNumber)?.intValue, result: result)
    case "delete":
      guard let args = call.arguments as? [String: Any],
            let locator = args["locator"] as? String else {
        result(FlutterError(code: "bad_arguments", message: "delete needs a locator", details: nil))
        return
      }
      delete(locator: locator, result: result)
    case "pick":
      let limit = ((call.arguments as? [String: Any])?["limit"] as? NSNumber)?.intValue ?? 0
      pick(limit: limit, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - The library

  private func open(result: @escaping FlutterResult) {
    let support = Self.supportDirectory()
    let temporary = FileManager.default.temporaryDirectory

    requestAccess { [weak self] allowed in
      guard let self else { return }
      guard allowed else {
        DispatchQueue.main.async {
          result(self.openPayload(collection: nil, support: support, temporary: temporary))
        }
        return
      }
      self.ensureAlbum { collection in
        DispatchQueue.main.async {
          if collection == nil {
            result(FlutterError(code: "album_unavailable", message: "the Kallo album could not be opened", details: nil))
            return
          }
          result(self.openPayload(collection: collection, support: support, temporary: temporary))
        }
      }
    }
  }

  private func openPayload(collection: PHAssetCollection?, support: URL, temporary: URL) -> [String: Any] {
    return [
      "root": collection?.localIdentifier ?? "unavailable",
      "displayName": "Photos › \(Self.albumTitle)",
      "supportPath": support.path,
      "temporaryPath": temporary.path,
      "available": collection != nil,
    ]
  }

  private func list(result: @escaping FlutterResult) {
    guard let collection = album() else {
      result([])
      return
    }
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    let assets = PHAsset.fetchAssets(in: collection, options: options)
    var rows: [[String: Any]] = []
    rows.reserveCapacity(assets.count)
    assets.enumerateObjects { asset, _, _ in
      guard asset.mediaType == .image else { return }
      let resource = PHAssetResource.assetResources(for: asset).first
      let milliseconds = (asset.creationDate?.timeIntervalSince1970 ?? 0) * 1000
      let modified = (asset.modificationDate?.timeIntervalSince1970 ?? 0) * 1000
      rows.append([
        "locator": asset.localIdentifier,
        "name": resource?.originalFilename ?? "Kallo-\(asset.localIdentifier).jpg",
        "width": asset.pixelWidth,
        "height": asset.pixelHeight,
        "size": 0,
        "created": milliseconds,
        "modified": modified,
      ])
    }
    result(rows)
  }

  private func save(path: String, name: String, result: @escaping FlutterResult) {
    guard let collection = album() else {
      result(FlutterError(code: "no_album", message: "The Kallo album is not available.", details: nil))
      return
    }
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(FlutterError(code: "no_file", message: "The print is no longer there.", details: nil))
      return
    }
    var placeholderID: String?
    PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      let options = PHAssetResourceCreationOptions()
      options.originalFilename = name
      request.addResource(with: .photo, fileURL: url, options: options)
      if let placeholder = request.placeholderForCreatedAsset {
        placeholderID = placeholder.localIdentifier
        if let albumChange = PHAssetCollectionChangeRequest(for: collection) {
          albumChange.addAssets([placeholder] as NSArray)
        }
      }
    } completionHandler: { success, error in
      DispatchQueue.main.async {
        if success, let identifier = placeholderID {
          result(identifier)
        } else {
          result(FlutterError(
            code: "save_failed",
            message: error?.localizedDescription ?? "The print could not be saved to Photos.",
            details: nil
          ))
        }
      }
    }
  }

  private func materialize(locator: String, result: @escaping FlutterResult) {
    guard let asset = asset(locator: locator) else {
      result(FlutterError(code: "not_found", message: "The print is no longer in Photos.", details: nil))
      return
    }
    // `requestImageDataAndOrientation` returns the current rendered image; iOS
    // may hand back a re-encoded JPEG and drop the XMP packet. The resource's
    // own bytes are the file that was saved, marker and all.
    guard let resource = Self.originalResource(for: asset) else {
      result(FlutterError(code: "no_resource", message: "The print has no readable resource.", details: nil))
      return
    }
    let ext = (resource.originalFilename as NSString).pathExtension
    let suffix = ext.isEmpty ? "img" : ext
    let target = FileManager.default.temporaryDirectory
      .appendingPathComponent("kallo-\(UUID().uuidString).\(suffix)")
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = true
    PHAssetResourceManager.default().writeData(
      for: resource,
      toFile: target,
      options: options
    ) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "write_failed",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(target.path)
        }
      }
    }
  }

  private static func originalResource(for asset: PHAsset) -> PHAssetResource? {
    let resources = PHAssetResource.assetResources(for: asset)
    for type in [PHAssetResourceType.photo, .alternatePhoto, .fullSizePhoto] {
      if let resource = resources.first(where: { $0.type == type }) {
        return resource
      }
    }
    return resources.first
  }

  private func image(locator: String, width: Int?, result: @escaping FlutterResult) {
    guard let asset = asset(locator: locator) else {
      result(FlutterError(code: "not_found", message: "The print is no longer in Photos.", details: nil))
      return
    }
    let target = targetSize(for: asset, width: width)
    let options = PHImageRequestOptions()
    options.version = .current
    options.deliveryMode = .highQualityFormat
    options.resizeMode = width == nil ? .none : .exact
    options.isNetworkAccessAllowed = true
    var answered = false
    PHImageManager.default().requestImage(
      for: asset,
      targetSize: target,
      contentMode: .aspectFit,
      options: options
    ) { image, info in
      if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
        return
      }
      if answered { return }
      answered = true
      guard let image, let data = image.jpegData(compressionQuality: 0.9) else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "no_image",
            message: (info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "The print could not be rendered.",
            details: nil
          ))
        }
        return
      }
      DispatchQueue.main.async {
        result(FlutterStandardTypedData(bytes: data))
      }
    }
  }

  private func delete(locator: String, result: @escaping FlutterResult) {
    guard let asset = asset(locator: locator) else {
      result(nil)
      return
    }
    PHPhotoLibrary.shared().performChanges {
      PHAssetChangeRequest.deleteAssets([asset] as NSArray)
    } completionHandler: { success, error in
      DispatchQueue.main.async {
        if success {
          result(nil)
        } else {
          result(FlutterError(
            code: "delete_failed",
            message: error?.localizedDescription ?? "The print could not be removed from Photos.",
            details: nil
          ))
        }
      }
    }
  }

  // MARK: - The system picker

  private func pick(limit: Int, result: @escaping FlutterResult) {
    guard let presenter = Self.topViewController() else {
      result(FlutterError(code: "no_presenter", message: "No window to present the picker.", details: nil))
      return
    }
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = max(0, limit)
    configuration.preferredAssetRepresentationMode = .compatible
    let picker = PHPickerViewController(configuration: configuration)
    let delegate = KalloPickerDelegate { [weak self] paths in
      self?.pickerDelegate = nil
      result(paths)
    }
    pickerDelegate = delegate
    picker.delegate = delegate
    presenter.present(picker, animated: true)
  }

  // MARK: - PhotoKit

  private func requestAccess(completion: @escaping (Bool) -> Void) {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    switch status {
    case .authorized, .limited:
      completion(true)
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { next in
        completion(next == .authorized || next == .limited)
      }
    default:
      completion(false)
    }
  }

  private func ensureAlbum(completion: @escaping (PHAssetCollection?) -> Void) {
    if let existing = album() {
      completion(existing)
      return
    }
    var placeholder: PHObjectPlaceholder?
    PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
        withTitle: Self.albumTitle
      )
      placeholder = request.placeholderForCreatedAssetCollection
    } completionHandler: { success, _ in
      guard success, let identifier = placeholder?.localIdentifier,
            let created = PHAssetCollection.fetchAssetCollections(
              withLocalIdentifiers: [identifier],
              options: nil
            ).firstObject else {
        completion(nil)
        return
      }
      completion(created)
    }
  }

  private func album() -> PHAssetCollection? {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "title = %@", Self.albumTitle)
    return PHAssetCollection.fetchAssetCollections(
      with: .album,
      subtype: .any,
      options: options
    ).firstObject
  }

  private func asset(locator: String) -> PHAsset? {
    PHAsset.fetchAssets(withLocalIdentifiers: [locator], options: nil).firstObject
  }

  private func targetSize(for asset: PHAsset, width: Int?) -> CGSize {
    let sourceWidth = max(1, asset.pixelWidth)
    let sourceHeight = max(1, asset.pixelHeight)
    guard let width, width > 0 else {
      return CGSize(width: sourceWidth, height: sourceHeight)
    }
    let targetWidth = min(width, sourceWidth)
    let targetHeight = max(1, Int((Double(targetWidth) * Double(sourceHeight) / Double(sourceWidth)).rounded()))
    return CGSize(width: targetWidth, height: targetHeight)
  }

  private static func supportDirectory() -> URL {
    let manager = FileManager.default
    let url = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? manager.temporaryDirectory
    try? manager.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
      ?? scenes.first?.windows.first
    guard var top = window?.rootViewController else { return nil }
    while let presented = top.presentedViewController {
      top = presented
    }
    return top
  }
}

private final class KalloPickerDelegate: NSObject, PHPickerViewControllerDelegate {
  init(completion: @escaping ([String]) -> Void) {
    self.completion = completion
  }

  private let completion: ([String]) -> Void

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard !results.isEmpty else {
      completion([])
      return
    }
    let group = DispatchGroup()
    var paths = [String?](repeating: nil, count: results.count)
    for (index, result) in results.enumerated() {
      group.enter()
      let provider = result.itemProvider
      let preferred = provider.registeredTypeIdentifiers.first { identifier in
        identifier == UTType.png.identifier ||
          identifier == UTType.jpeg.identifier ||
          identifier == UTType.heic.identifier
      }
      let type = preferred ?? UTType.image.identifier
      let suggested = provider.suggestedName
      let directory = Self.pickDirectory()
      provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
        defer { group.leave() }
        guard let url else { return }
        paths[index] = Self.copyPick(url, suggestedName: suggested, directory: directory)
      }
    }
    group.notify(queue: .main) {
      self.completion(paths.compactMap { $0 })
    }
  }

  func pickerDidCancel(_ picker: PHPickerViewController) {
    picker.dismiss(animated: true)
    completion([])
  }

  private static func pickDirectory() -> URL {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory
      .appendingPathComponent("kallo-pick-\(UUID().uuidString)", isDirectory: true)
    try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private static func copyPick(_ url: URL, suggestedName: String?, directory: URL) -> String? {
    let manager = FileManager.default
    let ext = url.pathExtension.lowercased()
    // The picker's own temporary name is a UUID. Keep the name the person
    // selected, so the print's title is `IMG_1234`, not `kallo-pick-...`.
    let raw = suggestedName ?? url.lastPathComponent
    let stem = sanitizeStem((raw as NSString).deletingPathExtension)
    if ext == "png" || ext == "jpg" || ext == "jpeg" {
      let named = directory.appendingPathComponent("\(stem).\(ext == "jpeg" ? "jpg" : ext)")
      do {
        try manager.copyItem(at: url, to: named)
        return named.path
      } catch {
        return nil
      }
    }
    guard let image = UIImage(contentsOfFile: url.path),
          let data = image.jpegData(compressionQuality: 0.95) else {
      return nil
    }
    let named = directory.appendingPathComponent("\(stem).jpg")
    do {
      try data.write(to: named, options: .atomic)
      return named.path
    } catch {
      return nil
    }
  }

  private static func sanitizeStem(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
    var cleaned = value
      .components(separatedBy: invalid)
      .joined(separator: "-")
      .components(separatedBy: .controlCharacters)
      .joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    cleaned = String(cleaned.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "print" : cleaned
  }
}
