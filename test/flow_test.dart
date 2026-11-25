import 'dart:io';

import 'package:flutter/material.dart';
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

  testWidgets('arrow keys swipe even when another widget has focus, but not under a sheet', (t) async {
    t.view.physicalSize = const Size(2400, 1600);
    t.view.devicePixelRatio = 1.5;
    addTearDown(t.view.reset);

    await t.pumpWidget(ImageDateApp(store: store, library: Library(store)));
    await settle(t);
    await t.tap(find.text('Walls'));
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // Start round 1 from the keyboard
    await settle(t);
    expect(find.byType(SwipeDeck), findsOneWidget);

    // Move keyboard focus to the "More" button, as a mouse click can do.
    final more = find.byTooltip('More');
    Focus.of(t.element(find.descendant(of: more, matching: find.byType(Icon)))).requestFocus();
    await t.pump();

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);
    expect(project.itemById(1)!.decisions[0], Decision.keep);

    // A held key swipes one card only.
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await settle(t);
    expect(project.itemById(2)!.decisions[0], Decision.reject);
    expect(project.itemById(3)!.decisions[0], isNull);

    // With the info sheet open, arrows do not swipe.
    await t.sendKeyEvent(LogicalKeyboardKey.keyI);
    await settle(t);
    expect(find.text('wall3.jpg'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await settle(t);
    expect(project.itemById(3)!.decisions[0], isNull);

    // Close the sheet; the up arrow now gives a Super Like.
    await t.tapAt(const Offset(20, 20));
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await settle(t);
    expect(project.itemById(3)!.decisions[0], Decision.superLike);
    await store.flush();
  });

  testWidgets('Endless: rounds go on, Stop shows the picks, Continue goes back', (t) async {
    project.maxRounds = null;
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(ImageDateApp(store: store, library: Library(store)));
    await settle(t);
    expect(find.text('Round 1 is ready · Endless'), findsOneWidget);
    await t.tap(find.text('Walls'));
    await settle(t);
    expect(find.text('ENDLESS'), findsOneWidget);
    await t.tap(find.text('Start'));
    await settle(t);
    expect(find.byTooltip('Super Like: keep for sure, skip all later rounds (↑)'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(t);
    }
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.textContaining('You kept every image in round 1.'), findsOneWidget);
    await t.tap(find.text('Start'));
    await settle(t);

    // Pass wall1, then keep wall2, then stop with the flag button.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);
    await t.tap(find.byTooltip('Stop and review (S)'));
    await settle(t);
    expect(project.stopped, isTrue);
    expect(find.text('2 picks'), findsOneWidget);
    expect(find.text('Stopped in round 2 · 1 not swiped yet'), findsOneWidget);

    await t.tap(find.text('Continue round 2'));
    await settle(t);
    expect(project.stopped, isFalse);
    expect(find.byType(SwipeDeck), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);

    // Round 3 and beyond: no limit. S stops from the round screen too.
    expect(find.text('Round 3'), findsOneWidget);
    await t.tap(find.text('Start'));
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);
    expect(find.text('Round 4'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await settle(t);
    expect(find.text('2 picks'), findsOneWidget);
    expect(find.text('Continue round 4'), findsNothing);
    expect(find.text('Start round 4'), findsOneWidget);
    await store.flush();
  });

  testWidgets('a finished 3-round project can keep going', (t) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    for (final i in project.items) {
      i.decisions.setAll(0, [Decision.keep, Decision.keep, Decision.keep]);
    }
    project.startedRound = 3;

    await t.pumpWidget(ImageDateApp(store: store, library: Library(store)));
    await settle(t);
    expect(find.text('Done · 3 picks'), findsOneWidget);
    await t.tap(find.text('Walls'));
    await settle(t);
    await t.tap(find.text('Keep going · round 4'));
    await settle(t);
    expect(project.isEndless, isTrue);
    expect(find.text('Round 4'), findsOneWidget);
    expect(find.text('ENDLESS'), findsOneWidget);
    await store.flush();
  });
}
