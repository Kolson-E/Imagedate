import 'package:flutter/material.dart';

import '../core/models.dart';
import '../platform/images.dart';
import 'add_images.dart';
import 'app_scope.dart';
import 'new_project_screen.dart';
import 'project_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _newProject(BuildContext context) async {
    final p = await Navigator.of(context).push<Project>(
      MaterialPageRoute(builder: (_) => const NewProjectScreen(), fullscreenDialog: true),
    );
    if (p != null && context.mounted) _openProject(context, p);
  }

  void _openProject(BuildContext context, Project p) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectScreen(project: p)));
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final projects = store.projects;
        return Scaffold(
          appBar: AppBar(
            centerTitle: false,
            titleSpacing: 20,
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppMark(size: 30),
                SizedBox(width: 10),
                GradientText('Image Date', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: projects.isEmpty
              ? _Empty(onNew: () => _newProject(context))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  itemCount: projects.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _ProjectCard(
                    project: projects[i],
                    onOpen: () => _openProject(context, projects[i]),
                  ),
                ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: projects.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420, minWidth: 420),
                    child: BrandButton(
                      label: 'New project',
                      icon: Icons.add_rounded,
                      onPressed: () => _newProject(context),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// The app's mark: two stacked cards with a heart.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: Transform.rotate(
              angle: -0.22,
              child: Container(
                margin: EdgeInsets.all(size * 0.1),
                decoration: BoxDecoration(
                  color: Palette.brandB.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(size * 0.18),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Transform.rotate(
              angle: 0.12,
              child: Container(
                margin: EdgeInsets.all(size * 0.1),
                decoration: BoxDecoration(
                  gradient: Palette.brand,
                  borderRadius: BorderRadius.circular(size * 0.18),
                ),
                child: Icon(Icons.favorite_rounded, color: Colors.white, size: size * 0.42),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppMark(size: 96),
              const SizedBox(height: 28),
              Text('Find the images\nyou really like',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.text, fontSize: 28, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 12),
              Text(
                'Pick a folder or album. Swipe through it three times. '
                'What is left is your final set.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 16, height: 1.45),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: BrandButton(label: 'New project', icon: Icons.add_rounded, onPressed: onNew),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onOpen});
  final Project project;
  final VoidCallback onOpen;

  String get _status {
    if (project.items.isEmpty) return 'No images';
    final r = project.currentRound;
    if (r == kDoneRound) return 'Done · ${plural(project.picks.length, 'pick')}';
    if (r > project.startedRound) return 'Round $r is ready';
    return 'Round $r';
  }

  Future<void> _rename(BuildContext context) async {
    final store = AppScope.of(context).store;
    final ctl = TextEditingController(text: project.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    project.name = name.trim();
    store.saveProject(project);
  }

  Future<void> _delete(BuildContext context) async {
    final store = AppScope.of(context).store;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${project.name}"?'),
        content: const Text('Your swipes for this project are lost. Your images are not deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Palette.nope),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await store.deleteProject(project);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final done = project.isDone && project.items.isNotEmpty;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Cover(project: project),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(plural(project.items.length, 'image'), style: TextStyle(color: p.muted, fontSize: 14)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: done ? Palette.brand : null,
                        color: done ? null : p.surfaceHigh,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_status,
                          style: TextStyle(
                              color: done ? Colors.white : p.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: p.muted),
                onSelected: (v) {
                  switch (v) {
                    case 'rename':
                      _rename(context);
                    case 'add':
                      showAddImagesSheet(context, project);
                    case 'delete':
                      _delete(context);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rename')),
                  ),
                  if (project.canAddImages)
                    const PopupMenuItem(
                      value: 'add',
                      child: ListTile(leading: Icon(Icons.add_photo_alternate_outlined), title: Text('Add images')),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded, color: Palette.nope),
                      title: Text('Delete project'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final library = AppScope.of(context).library;
    final picks = project.isDone ? project.picks : const <Item>[];
    final item = picks.isNotEmpty ? picks.first : project.items.firstOrNull;
    final placeholder = ColoredBox(
      color: p.surfaceHigh,
      child: Icon(Icons.photo_outlined, color: p.muted),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 76,
        height: 76,
        child: item == null
            ? placeholder
            : FutureBuilder(
                future: library.ensureOpen(project),
                builder: (context, snap) => snap.connectionState != ConnectionState.done
                    ? placeholder
                    : Image(
                        image: ItemImage(library, item, 256),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => placeholder,
                      ),
              ),
      ),
    );
  }
}
