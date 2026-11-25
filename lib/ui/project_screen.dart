import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/sorting.dart';
import '../core/store.dart';
import 'add_images.dart';
import 'app_scope.dart';
import 'info_sheet.dart';
import 'results_view.dart';
import 'settings_screen.dart';
import 'swipe/shake_detector.dart';
import 'swipe/swipe_deck.dart';
import 'theme.dart';

/// One project: round title screens, the swipe deck, and the results.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.project});
  final Project project;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  final _deck = GlobalKey<SwipeDeckState>();
  late final ShakeDetector _shake = ShakeDetector(_undo);
  bool _opened = false;
  List<Source> _missing = const [];
  bool _chrome = true; // landscape: show buttons over the image
  int? _pinnedId; // an undone image stays on top until it is decided again

  Project get p => widget.project;

  @override
  void initState() {
    super.initState();
    _open();
    // Keys work on this screen whatever widget has focus (Windows/keyboard).
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  late AppStore _store;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = AppScope.of(context).store;
    _updateShake();
  }

  @override
  void dispose() {
    _shake.stop();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _store.saveProjectNow(p);
    super.dispose();
  }

  void _updateShake() {
    if (_store.settings.shakeToUndo) {
      _shake.start();
    } else {
      _shake.stop();
    }
  }

  Future<void> _open() async {
    final scope = AppScope.of(context);
    final missing = await scope.library.ensureOpen(p);
    if (!mounted) return;
    setState(() {
      _opened = true;
      _missing = missing;
    });
  }

  Future<void> _relink(Source s) async {
    final scope = AppScope.of(context);
    final ok = await scope.library.relinkFolder(p, s);
    if (!ok || !mounted) return;
    scope.library.forget(p);
    setState(() => _missing = _missing.where((m) => m.id != s.id).toList());
    PaintingBinding.instance.imageCache.clear();
  }

  List<Item> _remaining(int round) {
    final list = p.remaining(round);
    final pin = _pinnedId;
    if (pin != null) {
      final i = list.indexWhere((x) => x.id == pin);
      if (i > 0) list.insert(0, list.removeAt(i));
    }
    return list;
  }

  void _decide(Item item, Decision d) {
    final store = AppScope.of(context).store;
    setState(() {
      p.decide(item, p.currentRound, d);
      if (_pinnedId == item.id) _pinnedId = null;
    });
    store.saveProject(p);
  }

  void _undo() {
    final last = p.lastSwipe;
    if (last == null) return;
    final store = _store;
    final item = p.undo();
    if (item == null) return;
    if (store.settings.haptics) HapticFeedback.mediumImpact();
    _pinnedId = item.id;
    // Bring the card back in from the side it left.
    final deck = _deck.currentState;
    if (deck != null) deck.flyIn(last.decision);
    setState(() {});
    if (deck == null) {
      // The deck was not on screen (round title or results): it is now.
      WidgetsBinding.instance.addPostFrameCallback((_) => _deck.currentState?.flyIn(last.decision));
    }
    store.saveProject(p);
  }

  /// Stops the rounds and shows what is still in the running.
  void _stop() {
    setState(() {
      p.stop();
      _pinnedId = null;
    });
    _store.saveProject(p);
  }

  void _start(int round) {
    setState(() => p.startedRound = round);
    AppScope.of(context).store.saveProject(p);
  }

  Future<void> _chooseOrder() async {
    final changed = await showSortSheet(context, p);
    if (changed && mounted) {
      setState(() => _pinnedId = null);
      AppScope.of(context).store.saveProject(p);
    }
  }

  Future<void> _addImages() async {
    await showAddImagesSheet(context, p);
    if (mounted) setState(() {});
  }

  void _info(Item item) => showInfoSheet(context, p, item);

  /// Keyboard: ← nope, → keep, ↑ Super Like (round 1), Ctrl+Z or Backspace
  /// undo, Space or Z zoom, I info, S stop and review, Esc back.
  /// Returns true when handled.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    // Only when this screen is on top (no sheet, dialog or other screen) and
    // no text field is being typed in.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    final focused = FocusManager.instance.primaryFocus?.context?.widget;
    if (focused is EditableText) return false;
    // Holding an arrow key does not swipe card after card.
    final repeat = e is KeyRepeatEvent;
    final round = p.currentRound;
    final done = p.isDone;
    final onDeck = !done && round <= p.startedRound;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return true;
    }
    if ((ctrl && k == LogicalKeyboardKey.keyZ) || k == LogicalKeyboardKey.backspace) {
      _undo();
      return true;
    }
    if (!onDeck) {
      if (done) return false;
      if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
        _start(round);
        return true;
      }
      if (k == LogicalKeyboardKey.keyS && round > 1) {
        _stop();
        return true;
      }
      return false;
    }
    if (k == LogicalKeyboardKey.keyS) {
      _stop();
      return true;
    }
    final deck = _deck.currentState;
    final isArrow = k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowUp;
    if (isArrow && repeat) return true;
    if (k == LogicalKeyboardKey.arrowLeft) {
      deck?.swipe(Decision.reject);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      deck?.swipe(Decision.keep);
    } else if (k == LogicalKeyboardKey.arrowUp && round == 1) {
      deck?.swipe(Decision.superLike);
    } else if (k == LogicalKeyboardKey.keyI) {
      final list = _remaining(round);
      if (list.isNotEmpty) _info(list.first);
    } else if (k == LogicalKeyboardKey.keyZ || k == LogicalKeyboardKey.space) {
      deck?.toggleZoom();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.store,
      builder: (context, _) {
        _updateShake();
        return _body(context);
      },
    );
  }

  Widget _body(BuildContext context) {
    if (!_opened) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (p.items.isEmpty) return _EmptyProject(project: p, onAdd: _addImages);
    final round = p.currentRound;
    if (p.isDone) {
      return ResultsView(
        project: p,
        onUndo: p.lastSwipe == null ? null : _undo,
        onChanged: () => setState(() {}),
      );
    }
    if (round > p.startedRound) {
      return _RoundIntro(
        project: p,
        round: round,
        onStart: () => _start(round),
        onOrder: _chooseOrder,
        onStop: round > 1 ? _stop : null,
      );
    }
    return _deckScreen(context, round);
  }

  Widget _deckScreen(BuildContext context, int round) {
    final scope = AppScope.of(context);
    final settings = scope.store.settings;
    final items = _remaining(round);
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final palette = Palette.of(context);

    final deck = SwipeDeck(
      key: _deck,
      library: scope.library,
      items: items,
      round: round,
      settings: settings,
      onDecide: _decide,
      borderRadius: landscape ? 0 : 20,
      onTap: landscape ? () => setState(() => _chrome = !_chrome) : null,
    );

    final top = _TopBar(
      title: 'Round $round',
      onBack: () => Navigator.of(context).maybePop(),
      onStop: _stop,
      menu: _menu(context),
      overImage: landscape,
    );
    final actions = _ActionBar(
      round: round,
      endless: p.isEndless,
      canUndo: p.lastSwipe != null,
      compact: landscape,
      onUndo: _undo,
      onReject: () => _deck.currentState?.swipe(Decision.reject),
      onSuper: () => _deck.currentState?.swipe(Decision.superLike),
      onKeep: () => _deck.currentState?.swipe(Decision.keep),
      onInfo: items.isEmpty ? null : () => _info(items.first),
    );

    final banner = _missing.isEmpty
        ? null
        : _MissingBanner(sources: _missing, onFind: _relink);

    if (!landscape) {
      return Scaffold(
        backgroundColor: palette.background,
        body: SafeArea(
          child: Column(
            children: [
              top,
              ?banner,
              Expanded(
                child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 4), child: deck),
              ),
              actions,
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: deck),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: _Scrim(top: true, child: SafeArea(bottom: false, child: Column(children: [top, ?banner]))),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: _Scrim(top: false, child: SafeArea(top: false, child: actions)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (v) {
        switch (v) {
          case 'order':
            _chooseOrder();
          case 'add':
            _addImages();
          case 'stop':
            _stop();
          case 'settings':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'order',
          child: ListTile(
            leading: const Icon(Icons.swap_vert_rounded),
            title: const Text('Order'),
            subtitle: Text(p.sort.label),
          ),
        ),
        const PopupMenuItem(
          value: 'stop',
          child: ListTile(leading: Icon(Icons.flag_rounded), title: Text('Stop and review (S)')),
        ),
        if (p.canAddImages)
          const PopupMenuItem(
            value: 'add',
            child: ListTile(leading: Icon(Icons.add_photo_alternate_outlined), title: Text('Add images')),
          ),
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(leading: Icon(Icons.tune_rounded), title: Text('Settings')),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ pieces

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onBack,
    required this.onStop,
    required this.menu,
    required this.overImage,
  });
  final String title;
  final VoidCallback onBack;
  final VoidCallback onStop;
  final Widget menu;
  final bool overImage;

  @override
  Widget build(BuildContext context) {
    final color = overImage ? Colors.white : Palette.of(context).text;
    return IconTheme(
      data: IconThemeData(color: color),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Projects',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            ),
            // Balances the two buttons on the right so the title stays centered.
            const SizedBox(width: 48),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Stop and review (S)',
              onPressed: onStop,
              icon: const Icon(Icons.flag_rounded),
            ),
            menu,
          ],
        ),
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.top, required this.child});
  final bool top;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
        ),
      ),
      child: Padding(padding: EdgeInsets.only(bottom: top ? 24 : 0, top: top ? 0 : 24), child: child),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.round,
    required this.endless,
    required this.canUndo,
    required this.compact,
    required this.onUndo,
    required this.onReject,
    required this.onSuper,
    required this.onKeep,
    required this.onInfo,
  });

  final int round;
  final bool endless;
  final bool canUndo;
  final bool compact;
  final VoidCallback onUndo;
  final VoidCallback onReject;
  final VoidCallback onSuper;
  final VoidCallback onKeep;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    final big = compact ? 56.0 : 68.0;
    final mid = compact ? 46.0 : 54.0;
    final small = compact ? 40.0 : 46.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 4 : 10, 16, compact ? 10 : 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RoundAction(
            size: small,
            icon: Icons.replay_rounded,
            color: Palette.superLike,
            tooltip: 'Undo last swipe (or shake)',
            onPressed: canUndo ? onUndo : null,
          ),
          SizedBox(width: compact ? 18 : 14),
          RoundAction(
            size: big,
            icon: Icons.close_rounded,
            color: Palette.nope,
            tooltip: 'Nope (←)',
            onPressed: onReject,
          ),
          if (round == 1) ...[
            SizedBox(width: compact ? 18 : 14),
            RoundAction(
              size: mid,
              icon: Icons.star_rounded,
              color: const Color(0xFF3BA7FF),
              tooltip: endless
                  ? 'Super Like: keep for sure, skip all later rounds (↑)'
                  : 'Super Like: keep for sure, skip rounds 2 and 3 (↑)',
              onPressed: onSuper,
            ),
          ],
          SizedBox(width: compact ? 18 : 14),
          RoundAction(
            size: big,
            icon: Icons.favorite_rounded,
            color: Palette.keep,
            tooltip: 'Keep (→)',
            onPressed: onKeep,
          ),
          SizedBox(width: compact ? 18 : 14),
          RoundAction(
            size: small,
            icon: Icons.info_outline_rounded,
            color: Palette.brandB,
            tooltip: 'Image info (I)',
            onPressed: onInfo,
          ),
        ],
      ),
    );
  }
}

/// A round dating-app style action button.
class RoundAction extends StatefulWidget {
  const RoundAction({
    super.key,
    required this.size,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final double size;
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<RoundAction> createState() => _RoundActionState();
}

class _RoundActionState extends State<RoundAction> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _down ? 0.88 : 1,
            duration: const Duration(milliseconds: 110),
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0.35,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: p.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.surfaceHigh, width: 1),
                  boxShadow: [BoxShadow(color: p.cardShadow, blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: Icon(widget.icon, color: widget.color, size: widget.size * 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingBanner extends StatelessWidget {
  const _MissingBanner({required this.sources, required this.onFind});
  final List<Source> sources;
  final void Function(Source) onFind;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            for (final s in sources)
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder_off_outlined, color: Palette.nope),
                title: Text('Cannot open the folder "${s.label}"'),
                subtitle: const Text('It was moved, renamed, or the drive is not connected.'),
                trailing: TextButton(onPressed: () => onFind(s), child: const Text('Find')),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundIntro extends StatelessWidget {
  const _RoundIntro({
    required this.project,
    required this.round,
    required this.onStart,
    required this.onOrder,
    required this.onStop,
  });
  final Project project;
  final int round;
  final VoidCallback onStart;
  final VoidCallback onOrder;
  final VoidCallback? onStop;

  String get _hint {
    if (!project.isEndless) {
      return switch (round) {
        1 => 'Swipe right to keep, left to pass.\nSwipe up to Super Like.\nA Super Like skips rounds 2 and 3.',
        2 => 'Only the images you kept.\nSwipe again.',
        _ => 'Last round.\nWhat you keep now is final.',
      };
    }
    if (round == 1) {
      return 'Swipe right to keep, left to pass.\nSwipe up to Super Like.\n'
          'A Super Like skips all later rounds.\nRounds go on until you tap Stop.';
    }
    final now = project.pool(round).length;
    final before = project.pool(round - 1).length;
    final same = now == before ? '\nYou kept every image in round ${round - 1}.' : '';
    return '${plural(now, 'image')} left.$same\nSwipe again, or stop and review.';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final hint = _hint;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Projects',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: Text(project.name),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (project.isEndless)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.all_inclusive_rounded, size: 18, color: p.muted),
                        const SizedBox(width: 6),
                        Text('ENDLESS',
                            style: TextStyle(
                                color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                      ],
                    )
                  else
                    _RoundDots(round: round, total: project.maxRounds!),
                  const SizedBox(height: 22),
                  GradientText('Round $round',
                      style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w900, height: 1.05)),
                  const SizedBox(height: 14),
                  Text(hint,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, fontSize: 16, height: 1.45)),
                  const SizedBox(height: 28),
                  ActionChip(
                    avatar: Icon(Icons.swap_vert_rounded, size: 18, color: p.text),
                    label: Text('Order: ${project.sort.label}'),
                    onPressed: onOrder,
                    backgroundColor: p.surface,
                    side: BorderSide(color: p.surfaceHigh),
                    shape: const StadiumBorder(),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(width: double.infinity, child: BrandButton(label: 'Start', onPressed: onStart)),
                  if (onStop != null) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: onStop,
                      icon: const Icon(Icons.flag_rounded, size: 18),
                      label: const Text('Stop and review'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundDots extends StatelessWidget {
  const _RoundDots({required this.round, required this.total});
  final int round;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 1; r <= total; r++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: r == round ? 28 : 8,
            height: 8,
            decoration: BoxDecoration(
              gradient: r <= round ? Palette.brand : null,
              color: r <= round ? null : p.surfaceHigh,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

class _EmptyProject extends StatelessWidget {
  const _EmptyProject({required this.project, required this.onAdd});
  final Project project;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined, size: 56, color: p.muted),
              const SizedBox(height: 16),
              Text('No images in this project', style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              BrandButton(label: 'Add images', icon: Icons.add_rounded, onPressed: onAdd),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet to choose the order of the remaining images.
Future<bool> showSortSheet(BuildContext context, Project project) async {
  final result = await showModalBottomSheet<(SortMode, bool)>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final pal = Palette.of(context);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text('Order',
                    style: TextStyle(color: pal.text, fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text('Changes the order of the images you have not swiped yet.',
                    style: TextStyle(color: pal.muted)),
              ),
              RadioGroup<SortMode>(
                groupValue: project.sort,
                onChanged: (m) => Navigator.pop(context, (m!, false)),
                child: Column(
                  children: [
                    for (final m in SortMode.values)
                      RadioListTile<SortMode>(
                        value: m,
                        title: Text(m.label),
                        activeColor: Palette.brandA,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, (SortMode.shuffle, true)),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Shuffle again'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (result == null) return false;
  final (mode, reshuffle) = result;
  if (reshuffle) project.seed = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
  project.sort = mode;
  return true;
}
