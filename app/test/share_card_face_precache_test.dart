import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/sharing/share_card_flow.dart';

void main() {
  testWidgets('preloads unique valid photos without changing the image format',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    final loaded = <String>[];

    await precacheShareCardFaces(
      context,
      ['photo-a', '', '  ', 'photo-a', 'photo-b'],
      imageLoader: (url) async => loaded.add(url),
    );

    expect(loaded, ['photo-a', 'photo-b']);
  });

  testWidgets('a failed photo never prevents the remaining faces loading',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    final loaded = <String>[];

    await precacheShareCardFaces(
      context,
      ['unreachable', 'good'],
      imageLoader: (url) async {
        if (url == 'unreachable') throw StateError('unreachable');
        loaded.add(url);
      },
    );

    expect(loaded, ['good']);
  });

  testWidgets('a stalled photo cannot block sharing beyond the deadline',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    final blocked = Completer<void>();
    final loaded = <String>[];

    final pending = precacheShareCardFaces(
      context,
      ['stalled', 'cached'],
      maxWait: const Duration(milliseconds: 100),
      imageLoader: (url) {
        if (url == 'stalled') return blocked.future;
        loaded.add(url);
        return Future<void>.value();
      },
    );

    await tester.pump(const Duration(milliseconds: 101));
    await pending;
    expect(loaded, ['cached']);

    // A late error belongs to that photo; it must not surface as an
    // unhandled asynchronous error after the share has already continued.
    blocked.completeError(StateError('late network failure'));
    await tester.pump();
  });
}
