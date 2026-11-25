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
  }) : decisions = decisions ?? List<Decision?>.filled(3, null);

  final int id;
  final String sourceId;
  final ItemKind kind;
  final String ref;
  final String name;

  /// Bytes. 0 when not known (Photos assets).
  final int size;

  /// Milliseconds since epoch (file modified, or photo taken).
  final int modified;

  /// Index 0, 1, 2 = round 1, 2, 3.
  final List<Decision?> decisions;

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
      decisions: [for (var i = 0; i < 3; i++) Decision.fromCode(codes[i])],
    );
  }
}

class LastSwipe {
  const LastSwipe(this.itemId, this.round, this.decision);
  final int itemId;
  final int round;
  final Decision decision;
}

/// Round number after the last round: the project is finished.
const int kDoneRound = 4;
const int kRounds = 3;

class Project {
  Project({
    required this.id,
    required this.name,
    required this.created,
    required this.seed,
    this.sort = SortMode.shuffle,
    this.startedRound = 0,
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

  /// The images that take part in [round] (1-3).
  Iterable<Item> pool(int round) {
    switch (round) {
      case 1:
        return items;
      case 2:
        return items.where((i) => i.decisions[0] == Decision.keep);
      case 3:
        return items.where((i) => i.decisions[1] == Decision.keep);
    }
    return const [];
  }

  /// Images in [round] that have no decision yet, in the project's sort order.
  List<Item> remaining(int round) {
    final list = pool(round).where((i) => i.decisions[round - 1] == null).toList();
    sortItems(list, sort, seed: seed, round: round);
    return list;
  }

  /// 1-3, or [kDoneRound] when all rounds are complete.
  int get currentRound {
    for (var r = 1; r <= kRounds; r++) {
      if (pool(r).any((i) => i.decisions[r - 1] == null)) return r;
    }
    return kDoneRound;
  }

  bool get isDone => currentRound == kDoneRound;

  /// Super likes from round 1 plus the images kept in round 3.
  List<Item> get picks => items
      .where((i) => i.decisions[0] == Decision.superLike || i.decisions[2] == Decision.keep)
      .toList();

  int get superLikeCount => items.where((i) => i.isSuperLike).length;

  /// Records a decision. Throws if it is not allowed.
  void decide(Item item, int round, Decision decision) {
    if (round < 1 || round > kRounds) throw ArgumentError('round $round');
    if (decision == Decision.superLike && round != 1) {
      throw ArgumentError('Super Like is only for round 1');
    }
    if (!pool(round).contains(item)) throw StateError('Item not in round $round');
    item.decisions[round - 1] = decision;
    lastSwipe = LastSwipe(item.id, round, decision);
  }

  /// Takes back the last swipe. Returns the item, or null if there is nothing to undo.
  Item? undo() {
    final last = lastSwipe;
    if (last == null) return null;
    final item = itemById(last.itemId);
    lastSwipe = null;
    if (item == null) return null;
    item.decisions[last.round - 1] = null;
    // A later round cannot have decisions for this item, but clear them to be safe.
    for (var r = last.round; r < kRounds; r++) {
      item.decisions[r] = null;
    }
    return item;
  }

  /// Takes an image out of the final picks (from the results screen).
  void removeFromPicks(Item item) {
    if (item.decisions[0] == Decision.superLike) {
      item.decisions[0] = Decision.reject;
    } else if (item.decisions[2] == Decision.keep) {
      item.decisions[2] = Decision.reject;
    }
    lastSwipe = null;
  }

  /// Clears all decisions. The images stay.
  void restart() {
    for (final i in items) {
      for (var r = 0; r < kRounds; r++) {
        i.decisions[r] = null;
      }
    }
    startedRound = 0;
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
        sources: [
          for (final s in (j['sources'] as List? ?? const [])) Source.fromJson(s as Map<String, dynamic>)
        ],
        items: [for (final i in (j['items'] as List? ?? const [])) Item.fromJson(i as List)],
      );
}
