import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'settings_widgets.dart';

/// Kept in sync with `pubspec.yaml` by hand: one string does not justify adding
/// `package_info_plus` (no new packages on this milestone).
const _appVersion = '2.7.0+1';

enum _LogLevel { off, warn, info, debug, trace }

/// Settings — "how does the app behave for me?".
///
/// Material 3 Expressive settings: every group has a tonal icon badge and a
/// `titleMedium` heading; rows lead with a smaller tonal badge; theme/language
/// are full-width `SegmentedButton`s; machine data sits on mono chips. Settings
/// apply immediately — there is no Save button. Capabilities that do not exist
/// yet stay honestly unavailable (M2 tooltip/badge) instead of faking success.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _serverController = TextEditingController();
  Future<String>? _coreVersion;
  _LogLevel _logLevel = _LogLevel.info;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _coreVersion ??= AppScope.read(context).client.version();
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final active = state.active;

    final sections = <Widget>[
      _appearance(state),
      _language(state),
      _core(),
      _configServer(),
      _logs(),
      _about(),
      if (active != null) _danger(active),
    ];

    return EtPage(
      title: 'Settings',
      subtitle: active?.config.instanceName ?? 'No network',
      child: EtScrollBody(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  constraints.maxWidth < 720 ? constraints.maxWidth : 720.0;
              return Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0) const SizedBox(height: EtSpace.x4),
                        sections[i],
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _appearance(AppState state) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    final reduced = context.etReducedMotion;
    return SettingsGroup(
      icon: Symbols.contrast,
      tone: EtTone.accent,
      title: 'Appearance',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsFieldLabel(
                icon: Symbols.palette,
                title: 'Theme',
                tone: EtTone.accent,
              ),
              const SizedBox(height: EtSpace.x2),
              SegmentedButton<ThemeMode>(
                style: SegmentedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: text.labelLarge,
                ),
                segments: const [
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                  ),
                ],
                selected: {state.themeMode},
                onSelectionChanged: (selection) =>
                    state.setThemeMode(selection.first),
                expandedInsets: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        const SizedBox(height: EtSpace.x2),
        const SettingsDivider(),
        SettingsRow(
          icon: Symbols.animation,
          tone: EtTone.info,
          title: 'Reduced motion',
          subtitle: 'Controlled by your system accessibility settings.',
          trailing: EtBadge(
            label: reduced ? 'Reduced' : 'Full',
            tone: reduced ? EtTone.info : EtTone.neutral,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EtSpace.x4,
            EtSpace.x1,
            EtSpace.x4,
            EtSpace.x2,
          ),
          child: Text(
            'The client always follows the system motion preference.',
            style: text.bodySmall?.copyWith(color: p.text2),
          ),
        ),
      ],
    );
  }

  Widget _language(AppState state) {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    return SettingsGroup(
      icon: Symbols.language,
      tone: EtTone.info,
      title: 'Language',
      subtitle: 'UI language (coming in M2)',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
          child: SegmentedButton<Locale>(
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(0, 52),
              textStyle: text.labelLarge,
            ),
            segments: const [
              ButtonSegment(value: Locale('en'), label: Text('English')),
              ButtonSegment(value: Locale('zh'), label: Text('中文')),
            ],
            selected: {state.locale},
            onSelectionChanged: (selection) => state.setLocale(selection.first),
            expandedInsets: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: EtSpace.x2),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EtSpace.x4,
            0,
            EtSpace.x4,
            EtSpace.x2,
          ),
          child: Text(
            'Strings are English-only until the M2 translation pass; the preference is stored now.',
            style: text.bodySmall?.copyWith(color: p.text2),
          ),
        ),
      ],
    );
  }

  Widget _core() {
    return SettingsGroup(
      icon: Symbols.memory,
      tone: EtTone.tertiary,
      title: 'Core',
      children: [
        FutureBuilder<String>(
          future: _coreVersion,
          builder: (context, snapshot) {
            final version = snapshot.hasError ? 'Unavailable' : snapshot.data;
            return SettingsRow(
              icon: Symbols.build,
              tone: EtTone.tertiary,
              title: 'Core version',
              trailing: SettingsMonoChip(text: version ?? 'Loading…'),
            );
          },
        ),
        const SettingsDivider(),
        const SettingsRow(
          icon: Symbols.info,
          tone: EtTone.info,
          title: 'Mode',
          subtitle: 'Runs the core inside the app process; no daemon connection.',
          footer: EtBadge(
            label: 'Normal (in-process)',
            tone: EtTone.success,
          ),
        ),
      ],
    );
  }

  Widget _configServer() {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    return SettingsGroup(
      icon: Symbols.cloud_sync,
      tone: EtTone.info,
      title: 'Config server',
      subtitle: 'Pull shared networks from a self-hosted server.',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
          child: Row(
            children: [
              const EtIconBadge(
                icon: Symbols.dns,
                tone: EtTone.info,
                size: 32,
              ),
              const SizedBox(width: EtSpace.x4),
              Expanded(
                child: EtTextField(
                  label: 'Server URL',
                  controller: _serverController,
                  hint: 'https://config.example.com',
                  helper: 'Stored locally. Fetching networks is not wired yet.',
                  mono: true,
                  keyboardType: TextInputType.url,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: EtSpace.x3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
          child: Tooltip(
            message: 'M2',
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Symbols.sync),
                label: const Text('Connect'),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EtSpace.x4,
            EtSpace.x1,
            EtSpace.x4,
            EtSpace.x2,
          ),
          child: Text(
            'Fetching networks arrives in M2.',
            style: text.bodySmall?.copyWith(color: p.text2),
          ),
        ),
      ],
    );
  }

  Widget _logs() {
    final p = context.et;
    final text = Theme.of(context).textTheme;
    return SettingsGroup(
      icon: Symbols.article,
      tone: EtTone.neutral,
      title: 'Logs',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
          child: Row(
            children: [
              const EtIconBadge(
                icon: Symbols.terminal,
                tone: EtTone.neutral,
                size: 32,
              ),
              const SizedBox(width: EtSpace.x4),
              Expanded(
                child: DropdownMenu<_LogLevel>(
                  initialSelection: _logLevel,
                  label: const Text('Log level'),
                  expandedInsets: EdgeInsets.zero,
                  textStyle: EtText.mono(size: EtType.bodySm, color: p.text),
                  dropdownMenuEntries: [
                    for (final level in _LogLevel.values)
                      DropdownMenuEntry<_LogLevel>(
                        value: level,
                        label: level.name,
                      ),
                  ],
                  onSelected: (next) {
                    if (next != null) setState(() => _logLevel = next);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: EtSpace.x2),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EtSpace.x4,
            0,
            EtSpace.x4,
            EtSpace.x2,
          ),
          child: Text(
            'Local only — the core does not receive this setting yet.',
            style: text.bodySmall?.copyWith(color: p.text2),
          ),
        ),
      ],
    );
  }

  Widget _about() {
    return SettingsGroup(
      icon: Symbols.info,
      tone: EtTone.tertiary,
      title: 'About',
      glow: true,
      children: [
        // Quiet expressive accent: the app version reads as a calm tonal chip
        // rather than another line of grey text.
        const SettingsRow(
          icon: Symbols.info,
          tone: EtTone.accent,
          title: 'App version',
          trailing: EtBadge(
            label: _appVersion,
            tone: EtTone.tertiary,
            icon: Symbols.verified,
          ),
        ),
        const SettingsDivider(),
        FutureBuilder<String>(
          future: _coreVersion,
          builder: (context, snapshot) {
            final version = snapshot.hasError ? 'Unavailable' : snapshot.data;
            return SettingsRow(
              icon: Symbols.build,
              tone: EtTone.neutral,
              title: 'Core version',
              trailing: SettingsMonoChip(text: version ?? 'Loading…'),
            );
          },
        ),
        const SettingsDivider(),
        const Tooltip(
          message: 'Coming in M2',
          child: SettingsRow(
            icon: Symbols.menu_book,
            tone: EtTone.info,
            title: 'Documentation',
            subtitle: 'easytier.top',
            trailing: EtBadge(label: 'M2'),
          ),
        ),
        const SettingsDivider(),
        const Tooltip(
          message: 'Coming in M2',
          child: SettingsRow(
            icon: Symbols.code,
            tone: EtTone.info,
            title: 'Source repository',
            subtitle: 'github.com/EasyTier/EasyTier',
            trailing: EtBadge(label: 'M2'),
          ),
        ),
      ],
    );
  }

  Widget _danger(NetworkInstance active) {
    return SettingsGroup(
      icon: Symbols.warning,
      tone: EtTone.danger,
      title: 'Danger zone',
      subtitle: 'Destructive actions. They cannot be undone.',
      children: [
        SettingsRow(
          icon: Symbols.delete,
          destructive: true,
          title: 'Delete this network',
          subtitle:
              'Removes “${active.config.networkName}” from this device and stops the tunnel.',
          onTap: _confirmDelete,
        ),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    final state = AppScope.read(context);
    final active = state.active;
    if (active == null) return;
    final p = context.et;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this network?'),
        content: Text(
          '“${active.config.networkName}” will be removed from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: p.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await state.removeInstance(active.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Network deleted')),
    );
  }
}
