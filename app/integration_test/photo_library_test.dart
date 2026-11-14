import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:kallo/lab/catalog.dart';
import 'package:kallo/lab/mobile_print_library.dart';
import 'package:kallo/lab/print_marker.dart';
import 'package:kallo/lab/print_meta.dart';
import 'package:kallo/lab/system_print_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the system library saves, lists, and materialises a print', (
    WidgetTester tester,
  ) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return;
    }
    final SystemPrintService service = SystemPrintService();
    final SystemLibraryInfo info = await service.open();
    expect(info.available, isTrue, reason: 'photo library access is required');

    final Directory work = Directory('${info.temporaryPath}/kallo-test');
    await work.create(recursive: true);
    final File file = File('${work.path}/integration.png');
    final img.Image picture = img.Image(width: 4, height: 3);
    img.fill(picture, color: img.ColorRgb8(120, 30, 10));
    await file.writeAsBytes(img.encodePng(picture));

    final DateTime now = DateTime.now().toUtc();
    final PrintMeta meta = PrintMeta(
      id: PrintMeta.newId(),
      title: 'integration print',
      kind: PrintKind.print,
      printed: now,
      added: now,
      updated: now,
    );
    final Catalog catalog = Catalog.openInMemory();
    final MobilePrintLibrary library = MobilePrintLibrary(
      service: service,
      catalog: catalog,
      library: catalog.ensureLibrary(
        kind: Platform.isIOS ? LibraryKind.iosAlbum : LibraryKind.androidFolder,
        root: info.root,
        displayName: info.displayName,
      ),
      info: info,
      workFolder: work,
      ownsCatalog: false,
    );

    String? locator;
    try {
      final saved = await library.addFile(file, meta);
      locator = saved.ref?.locator;
      expect(locator, isNotNull);

      final prints = await library.read();
      expect(prints.any((print) => print.id == meta.id), isTrue);

      final tempPath = await service.materialize(locator!);
      expect(tempPath, isNotNull);
      final File copy = File(tempPath!);
      expect((await PrintMarker.readMeta(copy))?.id, meta.id);
      await copy.delete();

      final bytes = await service.thumbnail(locator, 128);
      expect(bytes, isNotNull);
      expect(bytes, isNotEmpty);
    } finally {
      if (locator != null) {
        try {
          await service.delete(locator);
        } on Object {
          // The album is the person's; a test print left behind is visible but
          // harmless. The assertion above is what matters.
        }
      }
      catalog.close();
      if (await work.exists()) {
        await work.delete(recursive: true);
      }
    }
  });
}
