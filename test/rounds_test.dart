import 'package:flutter_test/flutter_test.dart';
import 'package:image_date/core/models.dart';
import 'package:image_date/core/sorting.dart';

Project makeProject(int n) {
  final p = Project(id: 't', name: 'Test', created: 0, seed: 42);
  for (var i = 1; i <= n; i++) {
    p.items.add(Item(
      id: i,
      sourceId: 's',
      kind: ItemKind.absFile,
      ref: '/img/$i.jpg',
      name: 'img$i.jpg',
      size: i * 100,
      modified: 1000 * (n - i),
    ));
  }
  return p;
}

/// Swipes every remaining image in the current round with [choose].
void playRound(Project p, Decision Function(Item) choose) {
  final round = p.currentRound;
  for (final item in p.remaining(round)) {
    p.decide(item, round, choose(item));
  }
}

void main() {
  test('three rounds narrow 1000 images down; super likes skip rounds 2 and 3', () {
    final p = makeProject(1000);
    expect(p.currentRound, 1);

    // Round 1: super like 1-10, keep 11-250, reject the rest.
    playRound(p, (i) => i.id <= 10
        ? Decision.superLike
        : i.id <= 250
            ? Decision.keep
            : Decision.reject);
    expect(p.currentRound, 2);
    expect(p.pool(2).length, 240, reason: 'super likes are not in round 2');

    // Round 2: reject 50.
    playRound(p, (i) => i.id <= 60 ? Decision.reject : Decision.keep);
    expect(p.currentRound, 3);
    expect(p.pool(3).length, 190);

    // Round 3: reject 15.
    playRound(p, (i) => i.id <= 75 ? Decision.reject : Decision.keep);
    expect(p.currentRound, 4);
    expect(p.roundsOver, isTrue);
    expect(p.isDone, isTrue);
    expect(() => p.decide(p.pool(4).first, 4, Decision.keep), throwsArgumentError,
        reason: 'a classic project has no round 4');
    expect(p.picks.length, 175 + 10);
    expect(p.picks.where((i) => i.isSuperLike).length, 10);
  });

  test('super like is refused after round 1', () {
    final p = makeProject(3);
    playRound(p, (_) => Decision.keep);
    expect(p.currentRound, 2);
    expect(() => p.decide(p.remaining(2).first, 2, Decision.superLike), throwsArgumentError);
  });

  test('undo takes back only the last swipe', () {
    final p = makeProject(5);
    final first = p.remaining(1)[0];
    final second = p.remaining(1)[1];
    p.decide(first, 1, Decision.keep);
    p.decide(second, 1, Decision.reject);
    expect(p.undo(), second);
    expect(second.decisions[0], isNull);
    expect(first.decisions[0], Decision.keep);
    expect(p.undo(), isNull, reason: 'only one level of undo');
  });

  test('undo after a round ends goes back into that round', () {
    final p = makeProject(3);
    playRound(p, (_) => Decision.keep);
    expect(p.currentRound, 2);
    p.undo();
    expect(p.currentRound, 1);
    expect(p.remaining(1).length, 1);
  });

  test('all rejected in round 1 ends the project with no picks', () {
    final p = makeProject(4);
    playRound(p, (_) => Decision.reject);
    expect(p.isDone, isTrue);
    expect(p.picks, isEmpty);
  });

  test('all super liked in round 1 ends the project at once', () {
    final p = makeProject(4);
    playRound(p, (_) => Decision.superLike);
    expect(p.isDone, isTrue);
    expect(p.picks.length, 4);
  });

  test('removeFromPicks and restart', () {
    final p = makeProject(4);
    playRound(p, (i) => i.id == 1 ? Decision.superLike : Decision.keep);
    playRound(p, (_) => Decision.keep);
    playRound(p, (_) => Decision.keep);
    expect(p.picks.length, 4);
    p.removeFromPicks(p.itemById(1)!);
    p.removeFromPicks(p.itemById(2)!);
    expect(p.picks.map((i) => i.id), [3, 4]);
    p.restart();
    expect(p.currentRound, 1);
    expect(p.startedRound, 0);
    expect(p.remaining(1).length, 4);
  });

  test('json round trip keeps decisions', () {
    final p = makeProject(6);
    p.decide(p.itemById(2)!, 1, Decision.superLike);
    p.decide(p.itemById(3)!, 1, Decision.reject);
    p.startedRound = 1;
    p.sort = SortMode.nameDesc;
    p.sources.add(Source(id: 's', kind: SourceKind.folder, label: 'Walls', bookmark: 'abc'));
    final q = Project.fromJson(p.toJson());
    expect(q.itemById(2)!.decisions, [Decision.superLike, null, null]);
    expect(q.itemById(3)!.decisions[0], Decision.reject);
    expect(q.startedRound, 1);
    expect(q.sort, SortMode.nameDesc);
    expect(q.sources.single.bookmark, 'abc');
    expect(q.items.length, 6);
  });

  group('endless', () {
    Project endless(int n) => makeProject(n)..maxRounds = null;

    test('rounds go on while images are kept', () {
      final p = endless(100);
      playRound(p, (i) => i.id <= 5 ? Decision.superLike : i.id <= 60 ? Decision.keep : Decision.reject);
      for (var r = 2; r <= 6; r++) {
        expect(p.currentRound, r);
        expect(p.isDone, isFalse);
        // Each round passes the 5 lowest ids still in the pool.
        final cut = p.pool(r).map((i) => i.id).reduce((a, b) => a < b ? a : b) + 5;
        playRound(p, (i) => i.id < cut ? Decision.reject : Decision.keep);
      }
      expect(p.currentRound, 7);
      expect(p.pool(7).length, 55 - 25);
      expect(p.picks.length, 30 + 5);
      expect(p.itemById(60)!.decisions.length, 6);
      expect(p.itemById(60)!.at(6), Decision.keep);
      expect(p.lastSwipedRound, 6);
    });

    test('keeping every image starts the same set again', () {
      final p = endless(3);
      playRound(p, (_) => Decision.keep);
      playRound(p, (_) => Decision.keep);
      playRound(p, (_) => Decision.keep);
      expect(p.currentRound, 4);
      expect(p.remaining(4).length, 3);
      expect(p.isDone, isFalse);
    });

    test('stop mid-round: picks are the kept and not yet swiped images; continue goes back', () {
      final p = endless(6);
      playRound(p, (i) => i.id == 1 ? Decision.superLike : Decision.keep);
      final r2 = p.remaining(2);
      p.decide(r2[0], 2, Decision.reject);
      p.decide(r2[1], 2, Decision.keep);
      p.stop();
      expect(p.isDone, isTrue);
      expect(p.canContinue, isTrue);
      expect(p.picks.length, 1 + 4, reason: '1 Super Like + 1 kept + 3 not swiped');
      expect(p.picks, isNot(contains(r2[0])));

      final q = Project.fromJson(p.toJson());
      expect(q.stopped, isTrue);
      expect(q.isEndless, isTrue);
      expect(q.picks.length, 5);

      p.resume();
      expect(p.isDone, isFalse);
      expect(p.currentRound, 2);
      expect(p.remaining(2).length, 3);
    });

    test('undo after stop takes back the swipe and continues', () {
      final p = endless(3);
      p.decide(p.remaining(1).first, 1, Decision.keep);
      p.stop();
      p.undo();
      expect(p.stopped, isFalse);
      expect(p.remaining(1).length, 3);
    });

    test('all passed ends Endless with nothing to continue', () {
      final p = endless(3);
      playRound(p, (_) => Decision.keep);
      playRound(p, (_) => Decision.reject);
      expect(p.isDone, isTrue);
      expect(p.picks, isEmpty);
      expect(p.canContinue, isFalse);
    });

    test('a finished classic project can keep going as Endless', () {
      final p = makeProject(10);
      playRound(p, (i) => i.id <= 8 ? Decision.keep : Decision.reject);
      playRound(p, (i) => i.id <= 6 ? Decision.keep : Decision.reject);
      playRound(p, (i) => i.id <= 5 ? Decision.keep : Decision.reject);
      expect(p.isDone, isTrue);
      expect(p.canContinue, isTrue);
      p.makeEndless();
      expect(p.isDone, isFalse);
      expect(p.currentRound, 4);
      expect(p.remaining(4).length, 5);
      playRound(p, (i) => i.id <= 2 ? Decision.keep : Decision.reject);
      expect(p.currentRound, 5);
      expect(p.picks.map((i) => i.id), [1, 2]);
      final q = Project.fromJson(p.toJson());
      expect(q.isEndless, isTrue);
      expect(q.itemById(1)!.at(4), Decision.keep);
      expect(q.currentRound, 5);
    });

    test('old project files load as classic', () {
      final j = makeProject(2).toJson()..remove('rounds')..remove('stopped');
      final q = Project.fromJson(j);
      expect(q.maxRounds, kClassicRounds);
      expect(q.stopped, isFalse);
    });
  });

  group('sorting', () {
    test('shuffle is stable for a seed and differs per round', () {
      final p = makeProject(50);
      final a = p.remaining(1).map((i) => i.id).toList();
      final b = p.remaining(1).map((i) => i.id).toList();
      expect(a, b);
      expect(a, isNot(List.generate(50, (i) => i + 1)));
      final r2 = [...p.items];
      sortItems(r2, SortMode.shuffle, seed: p.seed, round: 2);
      expect(r2.map((i) => i.id).toList(), isNot(a));
    });

    test('deciding an image does not change the order of the rest', () {
      final p = makeProject(30);
      final before = p.remaining(1).map((i) => i.id).toList();
      p.decide(p.itemById(before[0])!, 1, Decision.keep);
      expect(p.remaining(1).map((i) => i.id).toList(), before.sublist(1));
    });

    test('name sort is natural', () {
      final p = makeProject(12)..sort = SortMode.nameAsc;
      expect(p.remaining(1).take(3).map((i) => i.name), ['img1.jpg', 'img2.jpg', 'img3.jpg']);
      p.sort = SortMode.nameDesc;
      expect(p.remaining(1).first.name, 'img12.jpg');
    });

    test('date and size sorts', () {
      final p = makeProject(5)..sort = SortMode.newest;
      expect(p.remaining(1).first.id, 1);
      p.sort = SortMode.oldest;
      expect(p.remaining(1).first.id, 5);
      p.sort = SortMode.largest;
      expect(p.remaining(1).first.id, 5);
      p.sort = SortMode.smallest;
      expect(p.remaining(1).first.id, 1);
    });

    test('naturalCompare', () {
      expect(naturalCompare('a2', 'a10'), lessThan(0));
      expect(naturalCompare('A', 'a'), 0);
      expect(naturalCompare('x007', 'x7'), 0);
      expect(naturalCompare('abc', 'abcd'), lessThan(0));
    });
  });
}
