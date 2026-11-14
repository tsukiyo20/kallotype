import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kallo/app_info.dart';

void main() {
  test('the app version is the package version', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? found = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(found, isNotNull);
    expect(KalloInfo.version, found!.group(1));
  });
}
