import 'dart:io';

import 'catalog.dart';
import 'print.dart';
import 'print_meta.dart';

/// A library of prints, wherever the platform keeps them.
///
/// A desktop library is a folder of pictures; an iOS library is an album in
/// Photos; an Android library is `Pictures/Kallo` in MediaStore. The rooms do
/// not know which one is open. They ask for [read], and they get prints whose
/// pixels come from a source the platform understands.
///
/// The catalog is common to every implementation. So is the marker: a print
/// that leaves this device still carries its record. What changes is only how
/// a print is named ([CatalogPrint.locator]) and how its bytes are fetched.
abstract class PrintLibrary {
  /// The catalog this library's rows live in.
  Catalog get catalog;

  /// The catalog's row for this library.
  CatalogLibrary get library;

  /// Where the model writes a new print before the library adopts it.
  ///
  /// On desktop this is the export folder itself. On a phone it is a temporary
  /// folder: the system library is the destination, not a directory the model
  /// can write to.
  Directory get workFolder;

  /// The folder, when the platform library is a folder.
  ///
  /// Null on iOS and Android. A caller that needs a path has to be a desktop
  /// caller; the wall and the picker do not.
  Directory? get folder;

  /// Where the library is, in the words the platform uses.
  ///
  /// `~/Pictures/Kallo`, `Photos › Kallo`, `Pictures/Kallo`.
  String get locationLabel;

  /// Whether a folder chooser exists for this library.
  bool get canChooseFolder;

  /// Whether the platform lets the library see pictures other apps put in
  /// it. Desktop folders and a full photo-library grant do; Android's partial
  /// media access does not.
  bool get canListAll => true;

  /// Whether the platform has a system photo picker for this library.
  bool get canPickImages;

  /// Read the library and return the prints the rooms should hang.
  Future<List<Print>> read();

  /// Mark [file] and put it into the library.
  ///
  /// On desktop the file is already in the library and is marked in place. On
  /// a phone the marked bytes are saved to the system library, and [file] is a
  /// temporary file the caller can remove afterwards.
  Future<Print> addFile(File file, PrintMeta meta);

  /// Rewrite the marker for every print whose record is missing or behind the
  /// catalog and whose file still exists. Returns how many were repaired.
  Future<int> repairMarkers();

  /// Ask the platform for pictures. Empty when the person cancels.
  ///
  /// [limit] of zero means as many as the picker allows. Desktop returns an
  /// empty list: a folder library imports through the file panel instead.
  Future<List<File>> pickImages({int limit = 0});

  /// Release whatever the library owns. The catalog is closed only when this
  /// library opened it.
  void close();
}
