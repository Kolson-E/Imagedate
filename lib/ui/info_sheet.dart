import 'package:flutter/material.dart';

import '../core/models.dart';
import '../platform/images.dart';
import '../platform/native.dart';
import 'app_scope.dart';
import 'theme.dart';

/// Details of one image: name, place, format, size, date and round history.
Future<void> showInfoSheet(BuildContext context, Project project, Item item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _InfoSheet(project: project, item: item),
  );
}

class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.project, required this.item});
  final Project project;
  final Item item;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final library = AppScope.of(context).library;
    final source = project.sourceById(item.sourceId);
    final where = switch (item.kind) {
      ItemKind.asset => 'Photos · ${source?.label ?? ''}',
      ItemKind.folderFile => () {
          final i = item.ref.lastIndexOf('/');
          final sub = i < 0 ? '' : '/${item.ref.substring(0, i)}';
          return '${source?.label ?? 'Folder'}$sub';
        }(),
      ItemKind.appFile => 'Copy in Image Date',
      ItemKind.absFile => item.ref,
    };
    final date = item.modified == 0
        ? '—'
        : MaterialLocalizations.of(context).formatMediumDate(DateTime.fromMillisecondsSinceEpoch(item.modified));

    // Classic: rounds 1-3. Endless: every round so far.
    final cur = project.currentRound;
    final last = project.isEndless ? (cur > project.lastSwipedRound ? cur : project.lastSwipedRound) : kClassicRounds;
    final rounds = last < 1 ? 1 : last;

    String decision(int r) {
      final d = item.at(r + 1);
      if (r > 0 && item.isSuperLike) return 'Skipped (Super Like)';
      final inPool = project.pool(r + 1).contains(item);
      if (!inPool) return '—';
      return switch (d) {
        null => 'Not swiped yet',
        Decision.keep => 'Kept',
        Decision.reject => 'Passed',
        Decision.superLike => 'Super Like',
      };
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name,
                style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            _Row('Location', where),
            _Row('Format', item.extension.isEmpty ? '—' : item.extension.toUpperCase()),
            FutureBuilder<ImageSize?>(
              future: originalSize(library, item),
              builder: (context, snap) {
                final s = snap.data;
                final text = snap.connectionState != ConnectionState.done
                    ? '…'
                    : s == null
                        ? '—'
                        : '${s.width} × ${s.height}  ·  ${_shape(s)}';
                return _Row('Dimensions', text);
              },
            ),
            if (item.size > 0) _Row('File size', formatBytes(item.size)),
            _Row(item.kind == ItemKind.asset ? 'Taken' : 'Modified', date),
            const SizedBox(height: 12),
            Text('Rounds', style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (var r = 0; r < rounds; r++) _Row('Round ${r + 1}', decision(r)),
          ],
        ),
      ),
    );
  }

  static String _shape(ImageSize s) {
    if (s.width > s.height * 1.05) return 'Landscape';
    if (s.height > s.width * 1.05) return 'Portrait';
    return 'Square';
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: TextStyle(color: p.muted))),
          Expanded(child: SelectableText(value, style: TextStyle(color: p.text))),
        ],
      ),
    );
  }
}
