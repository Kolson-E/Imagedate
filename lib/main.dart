import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core/store.dart';
import 'platform/library.dart';
import 'ui/app_scope.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final store = AppStore(dir);
  await store.load();
  // Room for the current card, the next cards and some thumbnails.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 320 << 20;
  runApp(ImageDateApp(store: store, library: Library(store)));
}

class ImageDateApp extends StatefulWidget {
  const ImageDateApp({super.key, required this.store, required this.library});
  final AppStore store;
  final Library library;

  @override
  State<ImageDateApp> createState() => _ImageDateAppState();
}

class _ImageDateAppState extends State<ImageDateApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      widget.store.flush();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: widget.store,
      library: widget.library,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final mode = widget.store.settings.themeMode;
          return MaterialApp(
            title: 'Image Date',
            debugShowCheckedModeBanner: false,
            themeMode: mode,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            builder: (context, child) {
              final dark = Theme.of(context).brightness == Brightness.dark;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
                child: child!,
              );
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
