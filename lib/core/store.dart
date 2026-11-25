import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'settings.dart';

/// Keeps projects and settings as JSON files in the app's own storage.
/// Nothing here touches the user's original images.
class AppStore extends ChangeNotifier {
  AppStore(this.root);

  /// App storage folder (Application Support).
  final Directory root;

  AppSettings settings = AppSettings();
  final List<Project> projects = [];
  final Map<String, Timer> _pending = {};

  Directory get _projectsDir => Directory('${root.path}/projects');
  File get _settingsFile => File('${root.path}/settings.json');

  /// Folder for image copies that belong to one project (iOS file imports).
  Directory importsDir(String projectId) => Directory('${root.path}/imports/$projectId');

  Future<void> load() async {
    await _projectsDir.create(recursive: true);
    if (await _settingsFile.exists()) {
      try {
        settings = AppSettings.fromJson(
            jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('settings.json unreadable: $e');
      }
    }
    projects.clear();
    await for (final f in _projectsDir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        projects.add(Project.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Project file unreadable ${f.path}: $e');
      }
    }
    projects.sort((a, b) => b.created.compareTo(a.created));
    notifyListeners();
  }

  /// A new project that is not in the list yet (see [addProject]).
  Project draftProject(String name) {
    final rnd = Random();
    final id = '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${rnd.nextInt(1 << 30).toRadixString(36)}';
    return Project(
      id: id,
      name: name,
      created: DateTime.now().millisecondsSinceEpoch,
      seed: rnd.nextInt(1 << 31),
    );
  }

  Future<void> addProject(Project p) async {
    projects.insert(0, p);
    await saveProjectNow(p);
  }

  /// Removes the copies made for a draft project that was not started.
  Future<void> discardDraft(Project p) async {
    final imports = importsDir(p.id);
    if (await imports.exists()) await imports.delete(recursive: true);
  }

  /// Saves soon (many swipes in a row cause one write).
  void saveProject(Project p, {bool notify = true}) {
    _pending[p.id]?.cancel();
    _pending[p.id] = Timer(const Duration(milliseconds: 400), () => _write(p));
    if (notify) notifyListeners();
  }

  Future<void> saveProjectNow(Project p) async {
    _pending.remove(p.id)?.cancel();
    await _write(p);
    notifyListeners();
  }

  /// Writes all waiting saves at once (the app goes to the background).
  Future<void> flush() async {
    final ids = _pending.keys.toList();
    for (final id in ids) {
      _pending.remove(id)?.cancel();
      final p = projects.where((p) => p.id == id).firstOrNull;
      if (p != null) await _write(p);
    }
  }

  Future<void> _write(Project p) async {
    _pending.remove(p.id);
    final file = File('${_projectsDir.path}/${p.id}.json');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(p.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  /// Removes the project and the copies the app made for it.
  /// Original images in folders and in Photos are never touched.
  Future<void> deleteProject(Project p) async {
    _pending.remove(p.id)?.cancel();
    projects.remove(p);
    notifyListeners();
    final file = File('${_projectsDir.path}/${p.id}.json');
    if (await file.exists()) await file.delete();
    final imports = importsDir(p.id);
    if (await imports.exists()) await imports.delete(recursive: true);
  }

  Future<void> saveSettings() async {
    notifyListeners();
    final tmp = File('${_settingsFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(_settingsFile.path);
  }
}
