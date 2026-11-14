import 'dart:io';

import 'package:flutter/services.dart';

import 'print_ref.dart';

/// One picture the system library owns.
class SystemAsset {
  const SystemAsset({
    required this.locator,
    required this.name,
    required this.width,
    required this.height,
    required this.size,
    this.created,
    this.modified,
  });

  final String locator;
  final String name;
  final int width;
  final int height;
  final int size;
  final DateTime? created;
  final DateTime? modified;

  factory SystemAsset.fromMap(Map<Object?, Object?> map) {
    int number(Object? value) => (value as num?)?.toInt() ?? 0;
    DateTime? date(Object? value) {
      final int? millis = (value as num?)?.toInt();
      return millis == null || millis <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }

    return SystemAsset(
      locator: map['locator'] as String? ?? '',
      name: map['name'] as String? ?? 'print',
      width: number(map['width']),
      height: number(map['height']),
      size: number(map['size']),
      created: date(map['created']),
      modified: date(map['modified']),
    );
  }
}

/// What the platform says about the library it keeps for Kallo.
class SystemLibraryInfo {
  const SystemLibraryInfo({
    required this.root,
    required this.displayName,
    required this.supportPath,
    required this.temporaryPath,
    required this.available,
    this.canListAll = true,
  });

  /// The album's local identifier, or `Pictures/Kallo`.
  final String root;

  /// The name a person reads: `Photos › Kallo`, `Pictures/Kallo`.
  final String displayName;

  /// The app's support folder, where the catalog lives.
  final String supportPath;

  /// The app's temporary folder, where the model writes before adoption.
  final String temporaryPath;

  /// False when the photo library permission was denied. The app can still
  /// open; it has nothing to hang and cannot save until permission is granted.
  final bool available;

  /// False when the app may import and save but cannot see pictures other
  /// apps put in the library. Android's partial media access is this state.
  final bool canListAll;
}

/// The bridge to the one library the platform owns.
///
/// iOS implements this in `KalloPhotoLibrary.swift` with PhotoKit; Android
/// implements it in `KalloMediaStore.kt` with MediaStore. The protocol is the
/// same on both: a library has a root, a list of opaque locators, and bytes
/// that only the platform can fetch.
class SystemPrintService {
  SystemPrintService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.kallo.app/library');

  final MethodChannel _channel;

  Future<SystemLibraryInfo> open() async {
    final Map<Object?, Object?> map =
        await _channel.invokeMapMethod<Object?, Object?>('open') ??
        const <Object?, Object?>{};
    return SystemLibraryInfo(
      root: map['root'] as String? ?? 'unavailable',
      displayName: map['displayName'] as String? ?? 'Kallo',
      supportPath: map['supportPath'] as String? ?? '',
      temporaryPath: map['temporaryPath'] as String? ?? '',
      available: map['available'] != false,
      canListAll: map['canListAll'] != false,
    );
  }

  Future<List<SystemAsset>> list() async {
    final List<Object?> rows =
        await _channel.invokeListMethod<Object?>('list') ?? const <Object?>[];
    return <SystemAsset>[
      for (final Object? row in rows)
        if (row is Map<Object?, Object?>) SystemAsset.fromMap(row),
    ];
  }

  Future<String?> save(File file, String name) => _channel.invokeMethod<String>(
    'save',
    <String, Object?>{'path': file.path, 'name': name},
  );

  /// Write a local copy of [locator] and return it. The caller owns the file
  /// and deletes it after reading the marker.
  Future<String?> materialize(String locator) => _channel.invokeMethod<String>(
    'materialize',
    <String, Object?>{'locator': locator},
  );

  Future<Uint8List?> thumbnail(String locator, int width) => _bytes(
    'thumbnail',
    <String, Object?>{'locator': locator, 'width': width},
  );

  Future<Uint8List?> image(String locator, int? width) =>
      _bytes('image', <String, Object?>{'locator': locator, 'width': width});

  Future<void> delete(String locator) => _channel.invokeMethod<void>(
    'delete',
    <String, Object?>{'locator': locator},
  );

  Future<List<File>> pick({int limit = 0}) async {
    final List<Object?> paths =
        await _channel.invokeListMethod<Object?>('pick', <String, Object?>{
          'limit': limit,
        }) ??
        const <Object?>[];
    return <File>[
      for (final Object? path in paths)
        if (path is String) File(path),
    ];
  }

  Future<Uint8List?> _bytes(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final Object? result = await _channel.invokeMethod<Object?>(
      method,
      arguments,
    );
    if (result is Uint8List) {
      return result;
    }
    if (result is List<int>) {
      return Uint8List.fromList(result);
    }
    return null;
  }
}

/// A print whose pixels the platform fetches.
class SystemPrintRef implements PrintRef {
  const SystemPrintRef({
    required this.service,
    required this.locator,
    required this.name,
  });

  final SystemPrintService service;
  @override
  final String locator;
  @override
  final String name;

  @override
  Future<Uint8List?> thumbnail({required int maxWidth}) =>
      service.thumbnail(locator, maxWidth);

  @override
  Future<Uint8List?> image({int? maxWidth}) => service.image(locator, maxWidth);
}
