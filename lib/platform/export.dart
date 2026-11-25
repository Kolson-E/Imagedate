import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import '../core/models.dart';
import 'images.dart';
import 'library.dart';
import 'native.dart';

typedef Progress = void Function(int done, int total);

class ExportResult {
  ExportResult(this.done, this.failed, this.place);
  final int done;
  final List<String> failed;
  final String place;
}

String _safeName(String s) {
  final t = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
  return t.isEmpty ? 'Image Date' : t;
}

/// Asks for a folder. Returns its path, or null if cancelled.
Future<String?> pickExportFolder() async {
  if (Native.available) return (await Native.pickFolder())?.path;
  return pickDirectoryPath('Where to put the picks');
}

/// Copies the picks into a new folder "`project` picks" inside [parent].
/// The originals stay where they are.
Future<ExportResult> copyPicksToFolder(
  Library library,
  Project project,
  String parent, {
  Progress? onProgress,
}) async {
  final picks = project.picks;
  final sep = Platform.pathSeparator;
  final base = '${_safeName(project.name)} picks';
  var dir = Directory('$parent$sep$base');
  for (var n = 2; await dir.exists(); n++) {
    dir = Directory('$parent$sep$base $n');
  }
  await dir.create(recursive: true);

  final used = <String>{};
  final failed = <String>[];
  var done = 0;
  for (final item in picks) {
    try {
      final src = await originalFile(library, item);
      if (src == null || !await src.exists()) throw const FileSystemException('not found');
      var name = item.kind == ItemKind.asset ? src.uri.pathSegments.last : item.name;
      name = _safeName(name);
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      var candidate = name;
      for (var n = 2; !used.add(candidate.toLowerCase()); n++) {
        candidate = '$stem ($n)$ext';
      }
      await src.copy('${dir.path}$sep$candidate');
      done++;
    } catch (_) {
      failed.add(item.name);
    }
    onProgress?.call(done + failed.length, picks.length);
  }
  return ExportResult(done, failed, dir.path);
}

/// Puts the picks in a Photos album "Image Date · `project`" (iOS).
/// Photos already in the library are added to the album, not copied.
/// Images from files are saved to the library first.
Future<ExportResult> savePicksToAlbum(Library library, Project project, {Progress? onProgress}) async {
  final state = await PhotoManager.requestPermissionExtend(
    requestOption: const PermissionRequestOption(iosAccessLevel: IosAccessLevel.readWrite),
  );
  if (!state.hasAccess) throw StateError('No access to Photos');

  final title = 'Image Date · ${project.name}';
  final paths = await PhotoManager.getAssetPathList(type: RequestType.image, hasAll: false);
  AssetPathEntity? album;
  for (final a in paths) {
    if (a.name == title && a.albumType == 1) album = a;
  }
  album ??= await PhotoManager.editor.darwin.createAlbum(title);
  if (album == null) throw StateError('Could not make the album');

  final picks = project.picks;
  final failed = <String>[];
  var done = 0;
  for (final item in picks) {
    try {
      AssetEntity? asset;
      if (item.kind == ItemKind.asset) {
        asset = await AssetEntity.fromId(item.ref);
      } else {
        final path = library.pathFor(item);
        if (path == null) throw const FileSystemException('not found');
        asset = await PhotoManager.editor.saveImageWithPath(path, title: item.name);
      }
      if (asset == null) throw const FileSystemException('not found');
      await PhotoManager.editor.copyAssetToPath(asset: asset, pathEntity: album);
      done++;
    } catch (_) {
      failed.add(item.name);
    }
    onProgress?.call(done + failed.length, picks.length);
  }
  return ExportResult(done, failed, title);
}
