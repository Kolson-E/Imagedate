import 'models.dart';

enum SortMode {
  shuffle('Shuffle'),
  nameAsc('Name A–Z'),
  nameDesc('Name Z–A'),
  newest('Newest first'),
  oldest('Oldest first'),
  largest('Largest file first'),
  smallest('Smallest file first');

  const SortMode(this.label);
  final String label;
}

/// Sorts [items] in place. Shuffle order is stable for a given seed and round,
/// so the order does not jump when the app restarts or an image is decided.
void sortItems(List<Item> items, SortMode mode, {required int seed, required int round}) {
  int byName(Item a, Item b) {
    final c = naturalCompare(a.name, b.name);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  switch (mode) {
    case SortMode.shuffle:
      final s = seed ^ (round * 0x9E3779B1);
      final keys = {for (final i in items) i.id: _mix(s, i.id)};
      items.sort((a, b) {
        final c = keys[a.id]!.compareTo(keys[b.id]!);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    case SortMode.nameAsc:
      items.sort(byName);
    case SortMode.nameDesc:
      items.sort((a, b) => byName(b, a));
    case SortMode.newest:
      items.sort((a, b) {
        final c = b.modified.compareTo(a.modified);
        return c != 0 ? c : byName(a, b);
      });
    case SortMode.oldest:
      items.sort((a, b) {
        final c = a.modified.compareTo(b.modified);
        return c != 0 ? c : byName(a, b);
      });
    case SortMode.largest:
      items.sort((a, b) {
        final c = b.size.compareTo(a.size);
        return c != 0 ? c : byName(a, b);
      });
    case SortMode.smallest:
      items.sort((a, b) {
        final c = a.size.compareTo(b.size);
        return c != 0 ? c : byName(a, b);
      });
  }
}

/// 32-bit integer hash (splitmix-style), the same on every platform.
int _mix(int seed, int value) {
  var x = (seed ^ (value * 0x85EBCA6B)) & 0xFFFFFFFF;
  x = ((x ^ (x >> 16)) * 0x7FEB352D) & 0xFFFFFFFF;
  x = ((x ^ (x >> 15)) * 0x846CA68B) & 0xFFFFFFFF;
  return (x ^ (x >> 16)) & 0xFFFFFFFF;
}

/// Compares strings so that "img2" comes before "img10". Case-insensitive.
int naturalCompare(String a, String b) {
  final x = a.toLowerCase();
  final y = b.toLowerCase();
  var i = 0, j = 0;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i);
    final cy = y.codeUnitAt(j);
    if (_isDigit(cx) && _isDigit(cy)) {
      var ei = i, ej = j;
      while (ei < x.length && _isDigit(x.codeUnitAt(ei))) {
        ei++;
      }
      while (ej < y.length && _isDigit(y.codeUnitAt(ej))) {
        ej++;
      }
      final nx = x.substring(i, ei).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final ny = y.substring(j, ej).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (nx.length != ny.length) return nx.length.compareTo(ny.length);
      final c = nx.compareTo(ny);
      if (c != 0) return c;
      i = ei;
      j = ej;
    } else {
      if (cx != cy) return cx.compareTo(cy);
      i++;
      j++;
    }
  }
  return (x.length - i).compareTo(y.length - j);
}

bool _isDigit(int c) => c >= 48 && c <= 57;
