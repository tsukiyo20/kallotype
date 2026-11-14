import 'dart:io';

import 'catalog.dart';
import 'folder_print_library.dart';
import 'mobile_print_library.dart';
import 'print_library.dart';

/// Open the library this platform actually has.
///
/// The app asks once, at launch, and never branches on the platform again:
/// a desktop gets a folder, a phone gets the system photo library. Tests and
/// desktop code call [FolderPrintLibrary.open] directly.
Future<PrintLibrary> openPrintLibrary({
  Directory? folder,
  Catalog? catalog,
}) async {
  if (Platform.isIOS || Platform.isAndroid) {
    return MobilePrintLibrary.open(catalog: catalog);
  }
  if (folder == null) {
    throw ArgumentError('a desktop library needs a folder');
  }
  return FolderPrintLibrary.open(folder: folder, catalog: catalog);
}
