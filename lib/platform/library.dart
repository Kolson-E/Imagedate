import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/models.dart';
import '../core/store.dart';
import 'native.dart';

/// Image formats Flutter decodes itself, on every platform.
const flutterFormats = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'wbmp'};

/// Extra formats iOS decodes through ImageIO.
const iosFormats = {'heic', 'heif', 'avif', 'tif', 'tiff', 'dng'};

Set<String> get supportedFormats =>
    Platform.isIOS ? {...flutterFormats, ...iosFormats} : flutterFormats;

bool isSupportedImage(String name) {
  final i = name.lastIndexOf('.');
  if (i < 0) return false;
  return supportedFormats.contains(name.substring(i + 1).toLowerCase());
}

class ItemDraft {
  const ItemDraft(this.kind, this.ref, this.name, this.size, this.modified);
  final ItemKind kind;
  final String ref;
  final String name;
  final int size;
  final int modified;
}

class ImportResult {
  ImportResult(this.source, this.drafts, {this.waitingInCloud = 0});
  final Source source;
  final List<ItemDraft> drafts;

  /// iCloud Drive files that are not downloaded yet. They are asked to download
  /// and can be added later with "Add new images".
  final int waitingInCloud;
}

class FolderScan {
  FolderScan(this.drafts, this.cloudPlaceholders);
  final List<ItemDraft> drafts;

  /// Real paths of iCloud files that are still in the cloud.
  final List<String> cloudPlaceholders;
}

/// Finds the image files in [base] and all its subfolders.
/// Refs are relative to [base], with "/" separators.
Future<FolderScan> scanFolder(String base, {ItemKind kind = ItemKind.folderFile}) async {
  final drafts = <ItemDraft>[];
  final cloud = <String>[];
  final dir = Directory(base);
  final prefix = base.endsWith(Platform.pathSeparator) ? base : base + Platform.pathSeparator;

  Future<void> walk(Directory d) async {
    List<FileSystemEntity> entries;
    try {
      entries = await d.list(followLinks: false).toList();
    } catch (e) {
      debugPrint('Cannot list ${d.path}: $e');
      return;
    }
    for (final e in entries) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
      if (e is Directory) {
        if (!name.startsWith('.')) await walk(e);
        continue;
      }
      if (e is! File) continue;
      if (name.startsWith('.') && name.endsWith('.icloud')) {
        final real = name.substring(1, name.length - '.icloud'.length);
        if (isSupportedImage(real)) cloud.add('${e.parent.path}${Platform.pathSeparator}$real');
        continue;
      }
      if (name.startsWith('.') || !isSupportedImage(name)) continue;
      try {
        final st = await e.stat();
        final rel = e.path.startsWith(prefix) ? e.path.substring(prefix.length) : name;
        final ref = kind == ItemKind.absFile ? e.path : rel.replaceAll(r'\', '/');
        drafts.add(ItemDraft(kind, ref, name, st.size, st.modified.millisecondsSinceEpoch));
      } catch (err) {
        debugPrint('Cannot read ${e.path}: $err');
      }
    }
  }

  await walk(dir);
  return FolderScan(drafts, cloud);
}

/// Desktop folder picker. Returns a file system path, or null if cancelled.
Future<String?> pickDirectoryPath(String title) async {
  final uri = await FilePicker.pickDirectory(dialogTitle: title);
  if (uri == null) return null;
  return uri.toFilePath(windows: Platform.isWindows);
}

String _newSourceId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

String _folderName(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// Opens images for display: knows the current place of every folder source.
class Library {
  Library(this.store);
  final AppStore store;

  /// Source id → folder path in this app run.
  final Map<String, String> _folders = {};
  final Map<String, Future<List<Source>>> _opening = {};

  /// [openProject], done once per app run (call [forget] to try again).
  Future<List<Source>> ensureOpen(Project p) => _opening[p.id] ??= openProject(p);

  void forget(Project p) => _opening.remove(p.id);

  bool isFolderOpen(String sourceId) => _folders.containsKey(sourceId);

  /// Opens the folder sources of [p]. Returns the labels of folders that
  /// cannot be opened (moved, deleted, or the drive is not connected).
  Future<List<Source>> openProject(Project p) async {
    final failed = <Source>[];
    var changed = false;
    for (final s in p.sources.where((s) => s.kind == SourceKind.folder)) {
      if (_folders.containsKey(s.id)) continue;
      try {
        if (s.bookmark != null && Native.available) {
          final f = await Native.resolveBookmark(s.bookmark!);
          if (f.bookmark != null) {
            s.bookmark = f.bookmark;
            changed = true;
          }
          _folders[s.id] = f.path;
        } else if (s.path != null && await Directory(s.path!).exists()) {
          _folders[s.id] = s.path!;
        } else {
          failed.add(s);
        }
      } catch (e) {
        debugPrint('Cannot open folder ${s.label}: $e');
        failed.add(s);
      }
    }
    if (changed) store.saveProject(p, notify: false);
    return failed;
  }

  /// Absolute path of a file item, or null for Photos assets and folders that are not open.
  String? pathFor(Item item) {
    switch (item.kind) {
      case ItemKind.folderFile:
        final base = _folders[item.sourceId];
        if (base == null) return null;
        return '$base${Platform.pathSeparator}${item.ref.replaceAll('/', Platform.pathSeparator)}';
      case ItemKind.appFile:
        return '${store.root.path}/${item.ref}';
      case ItemKind.absFile:
        return item.ref;
      case ItemKind.asset:
        return null;
    }
  }

  // ---------------------------------------------------------------- imports

  /// Picks a folder and finds its images (subfolders too).
  Future<ImportResult?> importFolder() async {
    String path;
    String name;
    String? bookmark;
    if (Native.available) {
      final f = await Native.pickFolder();
      if (f == null) return null;
      path = f.path;
      name = f.name;
      bookmark = f.bookmark;
    } else {
      final picked = await pickDirectoryPath('Choose a folder of images');
      if (picked == null) return null;
      path = picked;
      name = _folderName(picked);
    }
    final source = Source(
      id: _newSourceId(),
      kind: SourceKind.folder,
      label: name,
      bookmark: bookmark,
      path: bookmark == null ? path : null,
    );
    _folders[source.id] = path;
    final scan = await scanFolder(path);
    if (scan.cloudPlaceholders.isNotEmpty && Native.available) {
      await Native.downloadICloud(scan.cloudPlaceholders);
    }
    return ImportResult(source, scan.drafts, waitingInCloud: scan.cloudPlaceholders.length);
  }

  /// Picks single image files. On iOS the picker gives copies; they are kept
  /// in the app's storage for this project. On desktop the files stay in place.
  Future<ImportResult?> importFiles(Project p) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose images',
      type: FileType.custom,
      allowedExtensions: supportedFormats.toList(),
    );
    final paths = files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return null;
    final source = Source(
      id: _newSourceId(),
      kind: SourceKind.files,
      label: paths.length == 1 ? _folderName(paths.first) : '${paths.length} files',
    );
    final drafts = <ItemDraft>[];
    if (Platform.isIOS) {
      final dir = store.importsDir(p.id);
      await dir.create(recursive: true);
      var n = DateTime.now().millisecondsSinceEpoch;
      for (final path in paths) {
        final name = _folderName(path);
        final fileName = '${(n++).toRadixString(36)}_$name';
        final copy = await File(path).copy('${dir.path}/$fileName');
        final st = await copy.stat();
        drafts.add(ItemDraft(ItemKind.appFile, 'imports/${p.id}/$fileName', name, st.size,
            st.modified.millisecondsSinceEpoch));
      }
      await FilePicker.clearTemporaryFiles();
    } else {
      for (final path in paths) {
        final st = await File(path).stat();
        drafts.add(ItemDraft(
            ItemKind.absFile, path, _folderName(path), st.size, st.modified.millisecondsSinceEpoch));
      }
    }
    return ImportResult(source, drafts);
  }

  /// All image albums in Photos, "Recents" first. Asks for access first.
  Future<List<AssetPathEntity>?> photoAlbums() async {
    final state = await PhotoManager.requestPermissionExtend();
    if (!state.hasAccess) return null;
    return PhotoManager.getAssetPathList(type: RequestType.image, hasAll: true);
  }

  /// Takes all images of the chosen albums. Photos are not copied; the app
  /// keeps their ids.
  Future<ImportResult> importAlbums(List<AssetPathEntity> albums) async {
    final seen = <String>{};
    final drafts = <ItemDraft>[];
    for (final album in albums) {
      final count = await album.assetCountAsync;
      for (var start = 0; start < count; start += 500) {
        final end = start + 500 > count ? count : start + 500;
        final assets = await album.getAssetListRange(start: start, end: end);
        for (final a in assets) {
          if (!seen.add(a.id)) continue;
          final title = a.title;
          drafts.add(ItemDraft(
            ItemKind.asset,
            a.id,
            (title == null || title.isEmpty) ? 'Photo' : title,
            0,
            a.createDateTime.millisecondsSinceEpoch,
          ));
        }
      }
    }
    final label = albums.length == 1 ? albums.first.name : '${albums.length} albums';
    return ImportResult(
      Source(id: _newSourceId(), kind: SourceKind.photos, label: label),
      drafts,
    );
  }

  /// Adds an import to a project. Images already in the project are skipped.
  /// Returns the number of images added.
  int addToProject(Project p, ImportResult r) {
    if (p.sourceById(r.source.id) == null) p.sources.add(r.source);
    final existing = {for (final i in p.items) '${i.kind.code}|${i.sourceId}|${i.ref}'};
    final assetIds = {for (final i in p.items.where((i) => i.kind == ItemKind.asset)) i.ref};
    final absPaths = {for (final i in p.items.where((i) => i.kind == ItemKind.absFile)) i.ref};
    var id = p.nextItemId;
    var added = 0;
    for (final d in r.drafts) {
      if (d.kind == ItemKind.asset && assetIds.contains(d.ref)) continue;
      if (d.kind == ItemKind.absFile && absPaths.contains(d.ref)) continue;
      if (!existing.add('${d.kind.code}|${r.source.id}|${d.ref}')) continue;
      if (d.kind == ItemKind.asset) assetIds.add(d.ref);
      if (d.kind == ItemKind.absFile) absPaths.add(d.ref);
      p.items.add(Item(
        id: id++,
        sourceId: r.source.id,
        kind: d.kind,
        ref: d.ref,
        name: d.name,
        size: d.size,
        modified: d.modified,
      ));
      added++;
    }
    // A source with no images left adds nothing to the project.
    if (!p.items.any((i) => i.sourceId == r.source.id)) p.sources.remove(r.source);
    return added;
  }

  /// Looks in the project's folders again and adds new images (round 1 only).
  /// Returns (added, still in iCloud).
  Future<(int, int)> rescanFolders(Project p) async {
    await openProject(p);
    var added = 0;
    var cloud = 0;
    for (final s in p.sources.where((s) => s.kind == SourceKind.folder).toList()) {
      final base = _folders[s.id];
      if (base == null) continue;
      final scan = await scanFolder(base);
      if (scan.cloudPlaceholders.isNotEmpty && Native.available) {
        await Native.downloadICloud(scan.cloudPlaceholders);
      }
      cloud += scan.cloudPlaceholders.length;
      added += addToProject(p, ImportResult(s, scan.drafts));
    }
    return (added, cloud);
  }

  /// Points a folder source that cannot be found to a new folder.
  Future<bool> relinkFolder(Project p, Source s) async {
    if (Native.available) {
      final f = await Native.pickFolder();
      if (f == null) return false;
      s.bookmark = f.bookmark;
      _folders[s.id] = f.path;
    } else {
      final picked = await pickDirectoryPath('Find the folder "${s.label}"');
      if (picked == null) return false;
      s.path = picked;
      _folders[s.id] = picked;
    }
    store.saveProject(p);
    return true;
  }
}
