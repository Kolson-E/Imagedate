import 'sorting.dart';

/// A choice made on one image in one round.
enum Decision {
  reject('r'),
  keep('k'),

  /// Only possible in round 1. The image goes straight to the final picks.
  superLike('s');

  const Decision(this.code);
  final String code;

  static Decision? fromCode(String c) {
    for (final d in Decision.values) {
      if (d.code == c) return d;
    }
    return null;
  }
}

/// Where a project's images come from.
enum SourceKind { folder, photos, files }

class Source {
  Source({
    required this.id,
    required this.kind,
    required this.label,
    this.bookmark,
    this.path,
  });

  final String id;
  final SourceKind kind;
  String label;

  /// iOS: security-scoped bookmark (base64) of a folder picked in Files.
  String? bookmark;

  /// Desktop: absolute folder path.
  String? path;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'label': label,
        if (bookmark != null) 'bookmark': bookmark,
        if (path != null) 'path': path,
      };

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        id: j['id'] as String,
        kind: SourceKind.values.byName(j['kind'] as String),
        label: j['label'] as String? ?? '',
        bookmark: j['bookmark'] as String?,
        path: j['path'] as String?,
      );
}

/// How [Item.ref] is read.
enum ItemKind {
  /// Path relative to the folder of its [Source].
  folderFile('f'),

  /// Path relative to the app's own storage (a copy made on import, iOS).
  appFile('a'),

  /// Absolute path (desktop).
  absFile('p'),

  /// Photos library asset id (iOS).
  asset('x');

  const ItemKind(this.code);
  final String code;

  static ItemKind fromCode(String c) =>
      ItemKind.values.firstWhere((k) => k.code == c);
}

class Item {
  Item({
    required this.id,
    required this.sourceId,
    required this.kind,
    required this.ref,
    required this.name,
    this.size = 0,
    this.modified = 0,
    List<Decision?>? decisions,
  }) : decisions = decisions ?? <Decision?>[null, null, null];

  final int id;
  final String sourceId;
  final ItemKind kind;
  final String ref;
  final String name;

  /// Bytes. 0 when not known (Photos assets).
  final int size;

  /// Milliseconds since epoch (file modified, or photo taken).
  final int modified;

  /// Index 0, 1, 2... = round 1, 2, 3... Grows in Endless mode.
  final List<Decision?> decisions;

  /// Decision in [round] (1-based), or null.
  Decision? at(int round) => round - 1 < decisions.length ? decisions[round - 1] : null;

  void set(int round, Decision? d) {
    while (decisions.length < round) {
      decisions.add(null);
    }
    decisions[round - 1] = d;
  }

  String get extension {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  bool get isSuperLike => decisions[0] == Decision.superLike;

  List<Object> toJson() => [
        id,
        sourceId,
        kind.code,
        ref,
        name,
        size,
        modified,
        decisions.map((d) => d?.code ?? '-').join(),
      ];

  factory Item.fromJson(List<dynamic> j) {
    final codes = j[7] as String;
    return Item(
      id: j[0] as int,
      sourceId: j[1] as String,
      kind: ItemKind.fromCode(j[2] as String),
      ref: j[3] as String,
      name: j[4] as String,
      size: j[5] as int,
      modified: j[6] as int,
      decisions: [
        for (var i = 0; i < (codes.length < 3 ? 3 : codes.length); i++)
          i < codes.length ? Decision.fromCode(codes[i]) : null
      ],
    );
  }
}

class LastSwipe {
  const LastSwipe(this.itemId, this.round, this.decision);
  final int itemId;
  final int round;
  final Decision decision;
}

/// Rounds in the classic mode.
const int kClassicRounds = 3;

class Project {
  Project({
    required this.id,
    required this.name,
    required this.created,
    required this.seed,
    this.sort = SortMode.shuffle,
    this.startedRound = 0,
    this.maxRounds = kClassicRounds,
    this.stopped = false,
    List<Source>? sources,
    List<Item>? items,
  })  : sources = sources ?? [],
        items = items ?? [];

  final String id;
  String name;
  final int created;

  /// Shuffle seed. A new seed gives a new shuffle.
  int seed;
  SortMode sort;

  /// The highest round the user has started (0 = none). When the current
  /// round is higher, the app shows the round's title screen first.
  int startedRound;

  /// 3 for the classic mode; null for Endless mode (rounds go on until you stop).
  int? maxRounds;

  /// The user stopped and looks at the picks so far. "Continue" clears it.
  bool stopped;

  bool get isEndless => maxRounds == null;

  final List<Source> sources;
  final List<Item> items;

  /// Only the last swipe can be undone. Not saved to disk.
  LastSwipe? lastSwipe;

  int get nextItemId =>
      items.isEmpty ? 1 : items.map((i) => i.id).reduce((a, b) => a > b ? a : b) + 1;

  Source? sourceById(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  Item? itemById(int id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// The images that take part in [round]: all images in round 1, then only
  /// the images kept in the round before. Super Likes leave after round 1.
  Iterable<Item> pool(int round) {
    if (round <= 1) return items;
    return items.where((i) => i.at(round - 1) == Decision.keep);
  }

  /// Images in [round] that have no decision yet, in the project's sort order.
  List<Item> remaining(int round) {
    final list = pool(round).where((i) => i.at(round) == null).toList();
    sortItems(list, sort, seed: seed, round: round);
    return list;
  }

  /// The round in front: the first round that still has images to swipe.
  /// When the rounds are over, it is the round after the last one; its pool
  /// is the set of survivors.
  int get currentRound {
    var r = 1;
    while (true) {
      final pool = this.pool(r);
      if (pool.isEmpty) return r;
      if (pool.any((i) => i.at(r) == null)) return r;
      final max = maxRounds;
      if (max != null && r >= max) return r + 1;
      r++;
    }
  }

  /// No round is left to swipe: the last classic round is complete, or no
  /// image is left in the running.
  bool get roundsOver {
    final r = currentRound;
    final max = maxRounds;
    if (max != null && r > max) return true;
    return !pool(r).any((i) => i.at(r) == null);
  }

  /// The picks screen shows: the user stopped, or no round is left.
  bool get isDone => stopped || roundsOver;

  /// Super Likes plus the images still in the running: in the current round,
  /// every image not passed yet (kept or not swiped yet).
  List<Item> get picks {
    final r = currentRound;
    final alive = pool(r).where((i) => i.at(r) != Decision.reject).toSet();
    return items.where((i) => i.isSuperLike || alive.contains(i)).toList();
  }

  int get superLikeCount => items.where((i) => i.isSuperLike).length;

  /// The last round in which the user swiped at least one image (0 = none).
  int get lastSwipedRound {
    var r = 0;
    for (final i in items) {
      for (var k = i.decisions.length; k > r; k--) {
        if (i.decisions[k - 1] != null) {
          r = k;
          break;
        }
      }
    }
    return r;
  }

  /// Records a decision. Throws if it is not allowed.
  void decide(Item item, int round, Decision decision) {
    final max = maxRounds;
    if (round < 1 || (max != null && round > max)) throw ArgumentError('round $round');
    if (decision == Decision.superLike && round != 1) {
      throw ArgumentError('Super Like is only for round 1');
    }
    if (!pool(round).contains(item)) throw StateError('Item not in round $round');
    item.set(round, decision);
    lastSwipe = LastSwipe(item.id, round, decision);
  }

  /// Takes back the last swipe. Returns the item, or null if there is nothing to undo.
  /// Undo after "Stop" also continues the rounds.
  Item? undo() {
    final last = lastSwipe;
    if (last == null) return null;
    final item = itemById(last.itemId);
    lastSwipe = null;
    if (item == null) return null;
    for (var r = last.round; r <= item.decisions.length; r++) {
      item.decisions[r - 1] = null;
    }
    stopped = false;
    return item;
  }

  /// Stops the rounds and shows the picks so far.
  void stop() {
    stopped = true;
  }

  /// Goes back to swiping after [stop].
  void resume() {
    stopped = false;
  }

  /// A classic project continues as Endless: round 4, 5... follow.
  void makeEndless() {
    maxRounds = null;
    stopped = false;
    lastSwipe = null;
  }

  /// True when "Continue" or "Keep going" has images to show.
  bool get canContinue {
    if (!stopped && !roundsOver) return false;
    final r = currentRound;
    final undecided = pool(r).any((i) => i.at(r) == null);
    if (undecided && (maxRounds == null || r <= maxRounds!)) return true;
    // Classic project with survivors: it can become Endless.
    return maxRounds != null && r > maxRounds! && pool(r).isNotEmpty;
  }

  /// Takes an image out of the picks (from the picks screen).
  void removeFromPicks(Item item) {
    if (item.isSuperLike) {
      item.set(1, Decision.reject);
    } else {
      final r = currentRound;
      if (pool(r).contains(item)) item.set(r, Decision.reject);
    }
    lastSwipe = null;
  }

  /// Clears all decisions. The images stay.
  void restart() {
    for (final i in items) {
      i.decisions
        ..clear()
        ..addAll([null, null, null]);
    }
    startedRound = 0;
    stopped = false;
    lastSwipe = null;
  }

  /// New images can be added only while round 1 is running.
  bool get canAddImages => currentRound == 1 || items.isEmpty;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'name': name,
        'created': created,
        'seed': seed,
        'sort': sort.name,
        'started': startedRound,
        'rounds': maxRounds,
        'stopped': stopped,
        'sources': sources.map((s) => s.toJson()).toList(),
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String,
        created: j['created'] as int,
        seed: j['seed'] as int,
        sort: SortMode.values.asNameMap()[j['sort']] ?? SortMode.shuffle,
        startedRound: j['started'] as int? ?? 0,
        maxRounds: j.containsKey('rounds') ? j['rounds'] as int? : kClassicRounds,
        stopped: j['stopped'] as bool? ?? false,
        sources: [
          for (final s in (j['sources'] as List? ?? const [])) Source.fromJson(s as Map<String, dynamic>)
        ],
        items: [for (final i in (j['items'] as List? ?? const [])) Item.fromJson(i as List)],
      );
}
