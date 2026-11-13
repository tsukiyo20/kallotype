import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/lab/model.dart';
import 'package:kallo_ui/lab/preview_bench.dart';

/// A session with no pixels: the bench's bookkeeping is what is under test.
class _Session implements PreviewSession {
  bool disposed = false;

  @override
  void dispose() => disposed = true;

  @override
  Future<ui.Image> frame({
    required double minutes,
    double? balanceFrom,
    double printEv = 0,
    String filters = '',
    String? heatGlass,
  }) async => throw UnimplementedError('the test never asks for pixels');
}

void main() {
  test('a session that arrives after the bench closes is let go', () async {
    final Completer<PreviewSession?> opening = Completer<PreviewSession?>();
    final PreviewBench bench = PreviewBench(open: () => opening.future);
    bench.warm();
    bench.dispose();

    final _Session session = _Session();
    opening.complete(session);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(session.disposed, isTrue);
  });

  test('a closed bench asks for nothing', () async {
    final PreviewBench bench = PreviewBench(
      open: () async => throw StateError('the bench is closed'),
    );
    bench.dispose();
    expect(
      await bench.frame(minutes: 6),
      isNull,
      reason: 'a closed bench has no session and no work',
    );
  });
}
