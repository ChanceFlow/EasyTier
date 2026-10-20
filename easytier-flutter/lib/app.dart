import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/state/app_state.dart';
import 'core/system_ui.dart';
import 'core/theme/theme.dart';
import 'core/ui/ui.dart';
import 'features/activity/activity_page.dart';
import 'features/config/config_page.dart';
import 'features/devices/devices_page.dart';
import 'features/home/home_page.dart';
import 'features/settings/settings_page.dart';

/// Root of the Flutter client. The whole app is rebuilt from one [AppState];
/// screens never construct their own core clients.
class EasytierApp extends StatelessWidget {
  const EasytierApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => AppScope(
        state: state,
        child: MaterialApp(
          title: 'EasyTier',
          debugShowCheckedModeBanner: false,
          theme: buildEtTheme(brightness: Brightness.light),
          darkTheme: buildEtTheme(brightness: Brightness.dark),
          themeMode: state.themeMode,
          // Keep the Android system bars in sync with the M3 surface (edge-to-edge).
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: etSystemUiOverlayStyle(Theme.of(context).brightness),
            child: child ?? const SizedBox.shrink(),
          ),
          home: const AppRoot(),
        ),
      ),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  EtDestination _current = EtDestination.home;
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    final state = AppScope.read(context);
    if (!state.initialized) {
      // Defer so the first frame paints the splash instead of blocking on I/O.
      WidgetsBinding.instance.addPostFrameCallback((_) => state.bootstrap());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.initialized) return const _Splash();

    return EtShell(
      current: _current,
      onSelect: (destination) => setState(() => _current = destination),
      activityBadge: state.events.length,
      child: IndexedStack(
        index: _current.index,
        children: const [
          HomePage(),
          DevicesPage(),
          ConfigPage(),
          ActivityPage(),
          SettingsPage(),
        ],
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Scaffold(
      backgroundColor: p.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: p.accentQuiet,
              child: Icon(Symbols.verified_user, size: 32, color: p.accentOnTint),
            ),
            const SizedBox(height: EtSpace.x5),
            Text(
              'EasyTier',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: EtSpace.x2),
            Text(
              'Starting core…',
              style: EtText.ui(size: EtType.bodySm, color: p.text3),
            ),
            const SizedBox(height: EtSpace.x6),
            // Determinate on purpose: an indeterminate bar schedules frames
            // forever, which makes every widget test (and golden) unable to
            // settle. The splash does not need to fake progress.
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: 0.55,
                minHeight: 2,
                backgroundColor: p.surface2,
                color: p.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
