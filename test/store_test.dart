import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_date/core/models.dart';
import 'package:image_date/core/store.dart';
import 'package:image_date/platform/export.dart';
import 'package:image_date/platform/library.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('imagedate_test'));
  tearDown(() async => tmp.delete(recursive: true));

  test('projects and settings survive a restart', () async {
    final store = AppStore(Directory('${tmp.path}/app'));
    await store.load();
    final p = store.draftProject('Walls');
    p.items.add(Item(id: 1, sourceId: 's', kind: ItemKind.absFile, ref: '/a.jpg', name: 'a.jpg'));
    await store.addProject(p);
    p.decide(p.items.first, 1, Decision.keep);
    store.saveProject(p);
    store.settings.fillWhenSideways = false;
    await store.saveSettings();
    await store.flush();

    final again = AppStore(Directory('${tmp.path}/app'));
    await again.load();
    expect(again.projects.single.name, 'Walls');
    expect(again.projects.single.items.single.decisions[0], Decision.keep);
    expect(again.settings.fillWhenSideways, isFalse);

    await again.deleteProject(again.projects.single);
    final third = AppStore(Directory('${tmp.path}/app'));
    await third.load();
    expect(third.projects, isEmpty);
  });

  test('scanFolder finds images in subfolders and skips other files', () async {
    final base = Directory('${tmp.path}/walls');
    await Directory('${base.path}/sub/deeper').create(recursive: true);
    await Directory('${base.path}/.hidden').create();
    final bytes = Uint8List.fromList([1, 2, 3]);
    for (final f in [
      'a.jpg',
      'B.PNG',
      'sub/c.webp',
      'sub/deeper/d.jpeg',
      'notes.txt',
      '.DS_Store',
      '.hidden/e.jpg',
      'sub/.f.jpg.icloud',
    ]) {
      await File('${base.path}/$f').writeAsBytes(bytes);
    }
    final scan = await scanFolder(base.path);
    final refs = scan.drafts.map((d) => d.ref).toList()..sort();
    expect(refs, ['B.PNG', 'a.jpg', 'sub/c.webp', 'sub/deeper/d.jpeg']);
    expect(scan.drafts.first.size, 3);
    expect(scan.cloudPlaceholders.single, endsWith('sub${Platform.pathSeparator}f.jpg'));
  });

  test('addToProject skips images already in the project', () async {
    final store = AppStore(Directory('${tmp.path}/app'));
    await store.load();
    final lib = Library(store);
    final p = store.draftProject('x');
    final src = Source(id: 's1', kind: SourceKind.folder, label: 'Walls', path: '/w');
    final r = ImportResult(src, const [
      ItemDraft(ItemKind.folderFile, 'a.jpg', 'a.jpg', 1, 1),
      ItemDraft(ItemKind.folderFile, 'b.jpg', 'b.jpg', 1, 1),
    ]);
    expect(lib.addToProject(p, r), 2);
    expect(lib.addToProject(p, r), 0);
    expect(p.items.map((i) => i.id), [1, 2]);
    expect(p.sources.length, 1);

    final photos = ImportResult(Source(id: 's2', kind: SourceKind.photos, label: 'Album'), const [
      ItemDraft(ItemKind.asset, 'X1', 'Photo', 0, 1),
      ItemDraft(ItemKind.asset, 'X1', 'Photo', 0, 1),
    ]);
    expect(lib.addToProject(p, photos), 1);

    final empty = ImportResult(Source(id: 's3', kind: SourceKind.files, label: 'none'), const []);
    expect(lib.addToProject(p, empty), 0);
    expect(p.sources.map((s) => s.id), ['s1', 's2'], reason: 'empty sources are not kept');
  });

  test('copyPicksToFolder copies only the picks and keeps the originals', () async {
    final store = AppStore(Directory('${tmp.path}/app'));
    await store.load();
    final lib = Library(store);
    final src = Directory('${tmp.path}/src')..createSync();
    final p = store.draftProject('Walls: best/2026');
    for (var i = 1; i <= 4; i++) {
      final name = i == 4 ? 'a.jpg' : 'w$i.jpg'; // w1 and a.jpg in different folders, same name
      final dir = i == 4 ? (Directory('${src.path}/sub')..createSync()) : src;
      final f = File('${dir.path}/${i == 4 ? 'w1.jpg' : name}')..writeAsStringSync('img$i');
      p.items.add(Item(id: i, sourceId: 's', kind: ItemKind.absFile, ref: f.path, name: i == 4 ? 'w1.jpg' : name));
    }
    p.decide(p.itemById(1)!, 1, Decision.superLike);
    for (final id in [2, 3, 4]) {
      p.decide(p.itemById(id)!, 1, Decision.keep);
    }
    p.decide(p.itemById(2)!, 2, Decision.reject);
    p.decide(p.itemById(3)!, 2, Decision.keep);
    p.decide(p.itemById(4)!, 2, Decision.keep);
    p.decide(p.itemById(3)!, 3, Decision.keep);
    p.decide(p.itemById(4)!, 3, Decision.keep);
    expect(p.picks.map((i) => i.id), [1, 3, 4]);

    final out = Directory('${tmp.path}/out')..createSync();
    final progress = <int>[];
    final r = await copyPicksToFolder(lib, p, out.path, onProgress: (d, _) => progress.add(d));
    expect(r.done, 3);
    expect(r.failed, isEmpty);
    expect(progress, [1, 2, 3]);
    expect(r.place, endsWith('Walls- best-2026 picks'));
    final names = Directory(r.place).listSync().map((e) => e.uri.pathSegments.last).toList()..sort();
    expect(names, ['w1 (2).jpg', 'w1.jpg', 'w3.jpg']);
    expect(src.listSync().whereType<File>().length, 3, reason: 'originals stay');

    // A second export makes a new folder instead of mixing files.
    final r2 = await copyPicksToFolder(lib, p, out.path);
    expect(r2.place, endsWith('Walls- best-2026 picks 2'));
  });
}
