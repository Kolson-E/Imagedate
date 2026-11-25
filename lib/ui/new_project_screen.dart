import 'package:flutter/material.dart';

import '../core/models.dart';
import 'add_images.dart';
import 'app_scope.dart';
import 'theme.dart';

/// Name the project and choose where the images come from.
/// Pops with the new project when the user taps Start.
class NewProjectScreen extends StatefulWidget {
  const NewProjectScreen({super.key});

  @override
  State<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends State<NewProjectScreen> {
  final _name = TextEditingController();
  late final Project _draft;
  bool _busy = false;
  bool _named = false;
  final _notes = <String, String>{}; // source id → note (iCloud downloads)

  @override
  void initState() {
    super.initState();
    final store = AppScope.of(context).store;
    _draft = store.draftProject('');
    _name.addListener(() {
      if (_name.text.isNotEmpty) _named = true;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add(ImportWay way) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await runImport(context, way, _draft);
      if (r == null || !mounted) return;
      final library = AppScope.of(context).library;
      final added = library.addToProject(_draft, r);
      if (r.waitingInCloud > 0) {
        _notes[r.source.id] = '${formatCount(r.waitingInCloud)} more still downloading from iCloud';
      }
      if (!_named && _name.text.isEmpty && _draft.sources.length == 1) {
        _name.text = r.source.label;
        _named = false;
      }
      if (added == 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.drafts.isEmpty ? 'No images found there.' : 'Those images are already added.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _removeSource(Source s) {
    setState(() {
      _draft.items.removeWhere((i) => i.sourceId == s.id);
      _draft.sources.remove(s);
    });
  }

  Future<void> _start() async {
    final store = AppScope.of(context).store;
    final name = _name.text.trim();
    _draft.name = name.isEmpty ? 'Project ${store.projects.length + 1}' : name;
    await store.addProject(_draft);
    if (mounted) Navigator.of(context).pop(_draft);
  }

  Future<bool> _confirmLeave() async {
    if (_draft.items.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave without starting?'),
        content: const Text('This project is not saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final count = _draft.items.length;
    return PopScope(
      canPop: _draft.items.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          await AppScope.of(context).store.discardDraft(_draft);
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const Text('New project'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: 'Project name',
                            filled: true,
                            fillColor: p.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('ADD IMAGES FROM',
                            style: TextStyle(
                                color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                        const SizedBox(height: 8),
                        for (final w in importWays)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: p.surface,
                              borderRadius: BorderRadius.circular(16),
                              child: ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                enabled: !_busy,
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: Palette.brand,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(w.icon, color: Colors.white, size: 22),
                                ),
                                title: Text(w.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(w.subtitle, style: TextStyle(color: p.muted, fontSize: 13)),
                                trailing: Icon(Icons.add_rounded, color: p.muted),
                                onTap: () => _add(w),
                              ),
                            ),
                          ),
                        if (_draft.sources.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('IN THIS PROJECT',
                              style: TextStyle(
                                  color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                          const SizedBox(height: 4),
                          for (final s in _draft.sources)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(switch (s.kind) {
                                SourceKind.folder => Icons.folder_rounded,
                                SourceKind.photos => Icons.photo_library_rounded,
                                SourceKind.files => Icons.image_rounded,
                              }),
                              title: Text(s.label),
                              subtitle: Text([
                                plural(_draft.items.where((i) => i.sourceId == s.id).length, 'image'),
                                ?_notes[s.id],
                              ].join(' · ')),
                              trailing: IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.remove_circle_outline_rounded),
                                onPressed: () => _removeSource(s),
                              ),
                            ),
                        ],
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: BrandButton(
                        label: count == 0 ? 'Add images to start' : 'Start · ${plural(count, 'image')}',
                        onPressed: count == 0 || _busy ? null : _start,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
