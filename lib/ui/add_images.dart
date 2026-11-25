import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/models.dart';
import '../platform/library.dart';
import 'app_scope.dart';
import 'theme.dart';

/// The ways to bring images in, for this platform.
enum ImportWay { photos, folder, files }

List<ImportWay> get importWays =>
    Platform.isIOS ? ImportWay.values : const [ImportWay.folder, ImportWay.files];

extension ImportWayText on ImportWay {
  IconData get icon => switch (this) {
        ImportWay.photos => Icons.photo_library_outlined,
        ImportWay.folder => Icons.folder_open_rounded,
        ImportWay.files => Icons.image_outlined,
      };

  String get title => switch (this) {
        ImportWay.photos => 'Photos albums',
        ImportWay.folder => Platform.isIOS ? 'Folder in Files' : 'Folder',
        ImportWay.files => 'Image files',
      };

  String get subtitle => switch (this) {
        ImportWay.photos => 'Pick one or more albums. Nothing is copied.',
        ImportWay.folder => 'All images in the folder and its subfolders. Nothing is copied.',
        ImportWay.files => Platform.isIOS
            ? 'Pick single images. The app keeps a copy.'
            : 'Pick single images. Nothing is copied.',
      };
}

/// Runs one import. Shows a progress dialog while the images are found.
/// Returns null if the user cancelled.
Future<ImportResult?> runImport(BuildContext context, ImportWay way, Project project) async {
  final library = AppScope.of(context).library;
  final messenger = ScaffoldMessenger.of(context);
  try {
    switch (way) {
      case ImportWay.photos:
        final albums = await library.photoAlbums();
        if (!context.mounted) return null;
        if (albums == null) {
          messenger.showSnackBar(const SnackBar(
              content: Text('Image Date has no access to Photos. Allow it in Settings › Image Date › Photos.')));
          return null;
        }
        final chosen = await showAlbumPicker(context, albums);
        if (chosen == null || chosen.isEmpty || !context.mounted) return null;
        return await _withProgress(context, library.importAlbums(chosen));
      case ImportWay.folder:
        final future = library.importFolder();
        return await future;
      case ImportWay.files:
        return await library.importFiles(project);
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not add images: $e')));
    return null;
  }
}

Future<T> _withProgress<T>(BuildContext context, Future<T> work) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 18),
          Expanded(child: Text('Finding images…')),
        ]),
      ),
    ),
  );
  try {
    return await work;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

String importSummary(int added, ImportResult r) {
  final parts = <String>['Added ${plural(added, 'image')}'];
  final skipped = r.drafts.length - added;
  if (skipped > 0) parts.add('${formatCount(skipped)} already in the project');
  if (r.waitingInCloud > 0) {
    parts.add('${formatCount(r.waitingInCloud)} still downloading from iCloud (use "Add images › Look for new images" later)');
  }
  return parts.join(' · ');
}

/// Bottom sheet to add images to an existing project (round 1 only).
Future<void> showAddImagesSheet(BuildContext context, Project project) async {
  final scope = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (!project.canAddImages) {
    messenger.showSnackBar(const SnackBar(content: Text('Images can be added only during round 1.')));
    return;
  }
  final hasFolders = project.sources.any((s) => s.kind == SourceKind.folder);
  final choice = await showModalBottomSheet<Object>(
    context: context,
    builder: (context) {
      final p = Palette.of(context);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Add images', style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            if (hasFolders)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Look for new images'),
                subtitle: const Text('In the folders of this project'),
                onTap: () => Navigator.pop(context, 'rescan'),
              ),
            for (final w in importWays)
              ListTile(
                leading: Icon(w.icon),
                title: Text(w.title),
                subtitle: Text(w.subtitle),
                onTap: () => Navigator.pop(context, w),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'rescan') {
    final (added, cloud) = await _withProgress(context, scope.library.rescanFolders(project));
    scope.store.saveProject(project);
    messenger.showSnackBar(SnackBar(
        content: Text('Added ${plural(added, 'new image')}'
            '${cloud > 0 ? ' · ${formatCount(cloud)} still downloading from iCloud' : ''}')));
    return;
  }
  final r = await runImport(context, choice as ImportWay, project);
  if (r == null) return;
  final added = scope.library.addToProject(project, r);
  scope.store.saveProject(project);
  messenger.showSnackBar(SnackBar(content: Text(importSummary(added, r))));
}

/// Lets the user choose Photos albums. Returns the chosen albums.
Future<List<AssetPathEntity>?> showAlbumPicker(BuildContext context, List<AssetPathEntity> albums) {
  return showModalBottomSheet<List<AssetPathEntity>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AlbumPicker(albums: albums),
  );
}

class _AlbumPicker extends StatefulWidget {
  const _AlbumPicker({required this.albums});
  final List<AssetPathEntity> albums;

  @override
  State<_AlbumPicker> createState() => _AlbumPickerState();
}

class _AlbumPickerState extends State<_AlbumPicker> {
  final _chosen = <String>{};
  late final Future<List<(AssetPathEntity, int)>> _counts = Future.wait(
    widget.albums.map((a) async => (a, await a.assetCountAsync)),
  ).then((l) => l.where((e) => e.$2 > 0).toList());

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => FutureBuilder(
        future: _counts,
        builder: (context, snap) {
          final list = snap.data;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Choose albums',
                          style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: scroll,
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final (album, count) = list[i];
                          final on = _chosen.contains(album.id);
                          return CheckboxListTile(
                            value: on,
                            activeColor: Palette.brandA,
                            onChanged: (v) => setState(() => v! ? _chosen.add(album.id) : _chosen.remove(album.id)),
                            secondary: _AlbumCover(album: album),
                            title: Text(album.isAll ? 'All photos' : album.name),
                            subtitle: Text(plural(count, 'image')),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: BrandButton(
                      label: _chosen.isEmpty ? 'Choose albums' : 'Add ${plural(_chosen.length, 'album')}',
                      onPressed: _chosen.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context, widget.albums.where((a) => _chosen.contains(a.id)).toList()),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AlbumCover extends StatelessWidget {
  const _AlbumCover({required this.album});
  final AssetPathEntity album;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: FutureBuilder(
          future: album
              .getAssetListRange(start: 0, end: 1)
              .then((l) => l.isEmpty ? null : l.first.thumbnailDataWithSize(const ThumbnailSize.square(144))),
          builder: (context, snap) => snap.data == null
              ? ColoredBox(color: p.surfaceHigh)
              : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
        ),
      ),
    );
  }
}
