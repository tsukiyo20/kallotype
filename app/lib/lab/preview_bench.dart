import 'dart:ui' as ui;

import 'model.dart';

/// The session a bench holds, and the one it is replacing.
///
/// A stage comes and goes while the model's session is still being opened: a
/// person clicks develop, then clicks print, and the first session may not have
/// answered yet. The bench is the small piece of bookkeeping that keeps that
/// from freeing a session under a frame that is still being drawn: it counts
/// the frames in flight, retires a session only when the count reaches zero,
/// and closes a session that arrives after the stage has gone.
class PreviewBench {
  PreviewBench({required this.open});

  /// Open the model's session, or return null when the model has none.
  final Future<PreviewSession?> Function() open;

  PreviewSession? _session;
  Future<PreviewSession?>? _opening;
  final List<PreviewSession> _retired = <PreviewSession>[];
  int _busy = 0;
  bool _closed = false;

  /// Start reading the photograph before the first frame is asked for.
  ///
  /// The bench is opened while the step is still drawing, so the first drag of
  /// the ruler finds a decode already in progress rather than starting one.
  void warm() {
    if (!_closed) {
      _opening ??= _start();
    }
  }

  /// The print the model would make at this setting, or null when there is no
  /// session to make it in.
  Future<ui.Image?> frame({
    required double minutes,
    double? balanceFrom,
    double printEv = 0,
    String filters = '',
    String? heatGlass,
  }) async {
    if (_closed) {
      return null;
    }
    final PreviewSession? session = await (_opening ??= _start());
    if (session == null || _closed) {
      return null;
    }
    _busy++;
    try {
      return await session.frame(
        minutes: minutes,
        balanceFrom: balanceFrom,
        printEv: printEv,
        filters: filters,
        heatGlass: heatGlass,
      );
    } finally {
      _busy--;
      _release();
    }
  }

  Future<PreviewSession?> _start() async {
    PreviewSession? session;
    try {
      session = await open();
    } on Object catch (error) {
      Model.log('the preview session could not be opened: $error');
      return null;
    }
    if (_closed) {
      session?.dispose();
      return null;
    }
    _session = session;
    return session;
  }

  /// Close the session, or retire it until the frame in flight is finished.
  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    final PreviewSession? session = _session;
    _session = null;
    if (session != null) {
      if (_busy > 0) {
        _retired.add(session);
      } else {
        session.dispose();
      }
    }
  }

  void _release() {
    if (_busy > 0 || _retired.isEmpty) {
      return;
    }
    for (final PreviewSession session in _retired) {
      session.dispose();
    }
    _retired.clear();
  }
}
