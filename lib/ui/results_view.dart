import 'dart:io';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../platform/export.dart';
import '../platform/images.dart';
import 'app_scope.dart';
import 'info_sheet.dart';
import 'theme.dart';

/// The end of a project, or a stop: the picks. This is the "cleaned out"
/// folder: only the images still in the running (and the Super Likes).
/// From here the user can continue the rounds, or keep going (Endless).
class ResultsView extends StatefulWidget {
  const ResultsView({super.key, required this.project, required this.onUndo, required this.onChanged});
  final Project project;
  final VoidCallback? onUndo;
  final VoidCallback onChanged;

  @override
  State<ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<ResultsView> {
  Project get p => widget.project;

  Future<void> _export(Future<ExportResult> Function(Progress) run) async {
    final messenger = ScaffoldMessenger.of(context);
    final progress = ValueNotifier<(int, int)>((0, p.picks.length));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Exporting picks'),
          content: ValueListenableBuilder(
            valueListenable: progress,
            builder: (context, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2, color: Palette.brandA),
                const SizedBox(height: 12),
                Text('${formatCount(v.$1)} of ${formatCount(v.$2)}'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final r = await run((done, total) => progress.value = (done, total));
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final failed = r.failed.isEmpty ? '' : ' · ${formatCount(r.failed.length)} could not be read';
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text('${plural(r.done, 'image')} in "${r.place}"$failed'),
      ));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _copyToFolder() async {
    final library = AppScope.of(context).library;
    final parent = await pickExportFolder();
    if (parent == null || !mounted) return;
    await _export((progress) => copyPicksToFolder(library, p, parent, onProgress: progress));
  }

  Future<void> _saveToAlbum() async {
    final library = AppScope.of(context).library;
    await _export((progress) => savePicksToAlbum(library, p, onProgress: progress));
  }

  Future<void> _restart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start over?'),
        content: const Text('All swipes in this project are cleared. The images stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start over')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    p.restart();
    AppScope.of(context).store.saveProject(p);
    widget.onChanged();
  }

  void _continue() {
    if (p.stopped && !p.roundsOver) {
      p.resume();
    } else {
      p.makeEndless();
    }
    AppScope.of(context).store.saveProject(p);
    widget.onChanged();
  }

  void _open(int index) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PickViewer(project: p, initial: index),
      fullscreenDialog: true,
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final picks = p.picks;
    final library = AppScope.of(context).library;
    final supers = picks.where((i) => i.isSuperLike).length;
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 130).floor().clamp(3, 8);
    final round = p.currentRound;
    final midRound = p.stopped && !p.roundsOver;
    final unswiped = midRound ? p.remaining(round).length : 0;
    final String? continueLabel = !p.canContinue
        ? null
        : midRound
            ? (round <= p.startedRound ? 'Continue round $round' : 'Start round $round')
            : 'Keep going · round $round';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Projects',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: Text(p.name),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (v) {
              if (v == 'restart') _restart();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'restart',
                child: ListTile(leading: Icon(Icons.restart_alt_rounded), title: Text('Start over')),
              ),
            ],
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  GradientText(plural(picks.length, 'pick'),
                      style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, height: 1.1)),
                  const SizedBox(height: 6),
                  Text(
                    'from ${plural(p.items.length, 'image')}'
                    '${supers > 0 ? ' · ${plural(supers, 'Super Like')}' : ''}',
                    style: TextStyle(color: pal.muted, fontSize: 15),
                  ),
                  if (p.stopped)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Stopped in round $round'
                        '${unswiped > 0 ? ' · ${formatCount(unswiped)} not swiped yet' : ''}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: pal.muted, fontSize: 13.5),
                      ),
                    ),
                  if (widget.onUndo != null)
                    TextButton.icon(
                      onPressed: widget.onUndo,
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: const Text('Undo last swipe'),
                    ),
                  const SizedBox(height: 14),
                  if (continueLabel != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _continue,
                            icon: Icon(midRound ? Icons.play_arrow_rounded : Icons.all_inclusive_rounded),
                            label: Text(continueLabel),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: const StadiumBorder(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (picks.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        children: [
                          if (Platform.isIOS) ...[
                            SizedBox(
                              width: double.infinity,
                              child: BrandButton(
                                label: 'Save to a Photos album',
                                icon: Icons.photo_album_outlined,
                                onPressed: _saveToAlbum,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _copyToFolder,
                                icon: const Icon(Icons.drive_folder_upload_outlined),
                                label: const Text('Copy to a folder'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  shape: const StadiumBorder(),
                                ),
                              ),
                            ),
                          ] else
                            SizedBox(
                              width: double.infinity,
                              child: BrandButton(
                                label: 'Copy to a folder',
                                icon: Icons.drive_folder_upload_outlined,
                                onPressed: _copyToFolder,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text('Your original images are not moved or deleted.',
                              style: TextStyle(color: pal.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  if (picks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text(
                        p.isEndless ? 'No image is left.' : 'No image passed all three rounds.',
                        style: TextStyle(color: pal.muted),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(3, 0, 3, 24),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
              ),
              itemCount: picks.length,
              itemBuilder: (context, i) {
                final item = picks[i];
                return GestureDetector(
                  onTap: () => _open(i),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image(
                          image: ItemImage(library, item, 384),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          frameBuilder: (context, child, frame, sync) => frame == null && !sync
                              ? ColoredBox(color: pal.surfaceHigh)
                              : child,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: pal.surfaceHigh,
                            child: Icon(Icons.broken_image_outlined, color: pal.muted),
                          ),
                        ),
                      ),
                      if (item.isSuperLike)
                        const Positioned(
                          right: 5,
                          top: 5,
                          child: _StarBadge(),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StarBadge extends StatelessWidget {
  const _StarBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
      child: const Icon(Icons.star_rounded, size: 15, color: Color(0xFF3BA7FF)),
    );
  }
}

/// Full-screen view of the picks. Swipe sideways to move, pinch to zoom.
class PickViewer extends StatefulWidget {
  const PickViewer({super.key, required this.project, required this.initial});
  final Project project;
  final int initial;

  @override
  State<PickViewer> createState() => _PickViewerState();
}

class _PickViewerState extends State<PickViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late List<Item> _picks = widget.project.picks;
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _remove() {
    final scope = AppScope.of(context);
    final item = _picks[_index];
    widget.project.removeFromPicks(item);
    scope.store.saveProject(widget.project);
    setState(() {
      _picks = widget.project.picks;
      if (_index >= _picks.length) _index = _picks.length - 1;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Removed "${item.name}" from picks')));
    if (_picks.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    final mq = MediaQuery.of(context);
    final px = ((mq.size.longestSide * mq.devicePixelRatio).ceil() + 255) ~/ 256 * 256;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_picks.isEmpty ? '' : '${_index + 1} / ${_picks.length}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          if (_picks.isNotEmpty) ...[
            IconButton(
              tooltip: 'Image info',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => showInfoSheet(context, widget.project, _picks[_index]),
            ),
            IconButton(
              tooltip: 'Remove from picks',
              icon: const Icon(Icons.heart_broken_outlined),
              onPressed: _remove,
            ),
          ],
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: _picks.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 8,
          child: Center(
            child: Image(
              image: ItemImage(library, _picks[i], px.clamp(1024, 3072)),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}
