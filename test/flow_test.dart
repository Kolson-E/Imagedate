import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_date/core/models.dart';
import 'package:image_date/core/sorting.dart';
import 'package:image_date/core/store.dart';
import 'package:image_date/main.dart';
import 'package:image_date/platform/library.dart';
import 'package:image_date/ui/swipe/swipe_deck.dart';

/// Pumps frames for [ms] milliseconds (pumpAndSettle cannot be used: image
/// loading spinners never settle in the fake clock).
Future<void> settle(WidgetTester t, [int ms = 800]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Directory tmp;
  late AppStore store;
  late Project project;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('imagedate_flow');
    store = AppStore(tmp);
    await store.load();
    project = store.draftProject('Walls');
    for (var i = 1; i <= 3; i++) {
      project.items.add(Item(
        id: i,
        sourceId: 's',
        kind: ItemKind.absFile,
        ref: '${tmp.path}/missing$i.jpg',
        name: 'wall$i.jpg',
      ));
    }
    project.sort = SortMode.nameAsc;
    store.projects.add(project);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('swipe through three rounds with gestures, buttons, keys and undo', (t) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(ImageDateApp(store: store, library: Library(store)));
    await settle(t);
    expect(find.text('Walls'), findsOneWidget);
    expect(find.text('Round 1 is ready'), findsOneWidget);

    await t.tap(find.text('Walls'));
    await settle(t);
    expect(find.text('Round 1'), findsOneWidget);
    await t.tap(find.text('Start'));
    await settle(t);
    expect(find.byType(SwipeDeck), findsOneWidget);
    expect(find.byTooltip('Super Like: keep for sure, skip rounds 2 and 3 (↑)'), findsOneWidget);

    // wall1: drag right = keep.
    await t.fling(find.byType(SwipeDeck), const Offset(500, 0), 2000);
    await settle(t);
    expect(project.itemById(1)!.decisions[0], Decision.keep);

    // wall2: button = nope.
    await t.tap(find.byTooltip('Nope (←)'));
    await settle(t);
    expect(project.itemById(2)!.decisions[0], Decision.reject);

    // wall3: drag up = super like. Round 1 ends.
    await t.fling(find.byType(SwipeDeck), const Offset(0, -700), 2000);
    await settle(t);
    expect(project.itemById(3)!.decisions[0], Decision.superLike);
    expect(find.text('Round 2'), findsOneWidget);

    // Undo from the round 2 title goes back to the wall3 card in round 1.
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await settle(t);
    expect(project.itemById(3)!.decisions[0], isNull);
    expect(find.text('Round 1'), findsOneWidget);
    expect(find.byType(SwipeDeck), findsOneWidget);

    // A short drag snaps back and decides nothing.
    await t.drag(find.byType(SwipeDeck), const Offset(40, 0));
    await settle(t);
    expect(project.itemById(3)!.decisions[0], isNull);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(t);
    expect(project.itemById(3)!.decisions[0], Decision.reject);

    // Round 2: only wall1. No Super Like button now.
    expect(find.text('Round 2'), findsOneWidget);
    await t.tap(find.text('Start'));
    await settle(t);
    expect(find.byTooltip('Super Like: keep for sure, skip rounds 2 and 3 (↑)'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp); // ignored in round 2
    await settle(t);
    expect(project.itemById(1)!.decisions[1], isNull);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);

    // Round 3.
    expect(find.text('Round 3'), findsOneWidget);
    await t.tap(find.text('Start'));
    await settle(t);
    await t.tap(find.byTooltip('Keep (→)'));
    await settle(t);

    expect(project.isDone, isTrue);
    expect(find.text('1 pick'), findsOneWidget);
    expect(find.text('Undo last swipe'), findsOneWidget);

    await store.flush();
  });
}
