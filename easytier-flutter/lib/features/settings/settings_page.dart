import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'logs_page.dart';
import 'settings_widgets.dart';

const _appVersion = '2.6.4+6';
const _logLevels = ['off', 'warn', 'info', 'debug', 'trace'];

/// Settings — global application preferences, core runtime diagnostics, and
/// version metadata.
///
/// Designed to commercial Material 3 standards (Pixel Settings / Tailscale):
/// quiet section labels without duplicate icon badges, grouped cards with
/// indented dividers, compact inline pill selectors for Theme/Language, and
/// bottom-sheet / menu pickers for Config Server and Log Level. Network-specific
/// actions (like deleting a network profile) live in Config where profiles are
/// managed.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<String>? _coreVersion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _coreVersion ??= AppScope.read(context).client.version();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return EtPage(
      title: 'Settings',
      subtitle: 'Preferences & core runtime',
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
                      _appearanceGroup(state),
                      const SizedBox(height: EtSpace.x4),
                      _coreGroup(state),
                      const SizedBox(height: EtSpace.x4),
                      _aboutGroup(),
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

  Widget _appearanceGroup(AppState state) {
    final reduced = context.etReducedMotion;
    return SettingsGroup(
      title: 'Appearance',
      children: [
        SettingsSegmentedRow<ThemeMode>(
          icon: Symbols.palette,
          tone: EtTone.accent,
          title: 'Theme',
          value: state.themeMode,
          options: const [
            (ThemeMode.dark, 'Dark'),
            (ThemeMode.light, 'Light'),
            (ThemeMode.system, 'System'),
          ],
          onChanged: state.setThemeMode,
        ),
        const SettingsDivider(),
        SettingsSegmentedRow<Locale>(
          icon: Symbols.language,
          tone: EtTone.info,
          title: 'Language',
          value: state.locale,
          options: const [
            (Locale('en'), 'English'),
            (Locale('zh'), '中文'),
          ],
          onChanged: state.setLocale,
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Symbols.animation,
          tone: EtTone.tertiary,
          title: 'Reduced motion',
          subtitle: 'System accessibility',
          trailing: EtBadge(
            label: reduced ? 'Reduced' : 'Standard',
            tone: reduced ? EtTone.info : EtTone.neutral,
          ),
        ),
      ],
    );
  }

  Widget _coreGroup(AppState state) {
    final p = context.et;
    final hasServer = state.configServerUrl.isNotEmpty;
    return SettingsGroup(
      title: 'Core & Networking',
      children: [
        const SettingsRow(
          icon: Symbols.memory,
          tone: EtTone.success,
          title: 'Execution mode',
          subtitle: 'In-process FFI tunnel',
          trailing: EtBadge(
            label: 'Normal (in-process)',
            tone: EtTone.success,
          ),
        ),
        const SettingsDivider(),
        SettingsRow(
          key: const Key('settings-config-server-row'),
          icon: Symbols.cloud_sync,
          tone: EtTone.info,
          title: 'Config server',
          subtitle: hasServer
              ? state.configServerUrl
              : 'Remote profile sync',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: context.etReducedMotion
                    ? Duration.zero
                    : EtDuration.fast,
                switchInCurve: EtCurves.enter,
                switchOutCurve: EtCurves.exit,
                child: EtBadge(
                  key: ValueKey<bool>(hasServer),
                  label: hasServer ? 'Configured' : 'Off',
                  tone: hasServer ? EtTone.accent : EtTone.neutral,
                ),
              ),
              const SizedBox(width: EtSpace.x1),
              Icon(Symbols.chevron_right, size: 18, color: p.text2),
            ],
          ),
          onTap: () => _openConfigServerSheet(state),
        ),
        const SettingsDivider(),
        MenuAnchor(
          builder: (context, controller, _) => SettingsRow(
            key: const Key('settings-log-level-row'),
            icon: Symbols.terminal,
            tone: EtTone.warn,
            title: 'Log level',
            subtitle: 'Core event verbosity',
            trailing: SettingsMonoChip(
              text: state.logLevel,
              icon: Symbols.expand_more,
            ),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
          menuChildren: [
            for (final level in _logLevels)
              MenuItemButton(
                onPressed: () => state.setLogLevel(level),
                leadingIcon: Icon(
                  state.logLevel == level
                      ? Symbols.check_circle
                      : Symbols.radio_button_unchecked,
                  size: 16,
                  color: state.logLevel == level ? p.accent : p.text2,
                ),
                child: Text(
                  level,
                  style: EtText.mono(size: EtType.bodySm, color: p.text),
                ),
              ),
          ],
        ),
        const SettingsDivider(),
        SettingsRow(
          key: const Key('settings-logs-row'),
          icon: Symbols.receipt_long,
          tone: EtTone.neutral,
          title: 'Client logs',
          subtitle: 'Lifecycle, RPC and config lines',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListenableBuilder(
                listenable: state.logs,
                builder: (context, _) => EtBadge(
                  label: '${state.logs.entries.length}',
                  tone: EtTone.neutral,
                ),
              ),
              const SizedBox(width: EtSpace.x1),
              Icon(Symbols.chevron_right, size: 18, color: p.text2),
            ],
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const LogsPage()),
          ),
        ),
      ],
    );
  }

  Widget _aboutGroup() {
    final p = context.et;
    return SettingsGroup(
      title: 'About',
      children: [
        const SettingsRow(
          icon: Symbols.verified_user,
          tone: EtTone.accent,
          title: 'App version',
          subtitle: 'Flutter client',
          trailing: SettingsMonoChip(text: _appVersion),
        ),
        const SettingsDivider(),
        FutureBuilder<String>(
          future: _coreVersion,
          builder: (context, snapshot) {
            final version = snapshot.hasError ? 'Unavailable' : snapshot.data;
            return SettingsRow(
              icon: Symbols.build,
              tone: EtTone.tertiary,
              title: 'Core version',
              subtitle: 'Embedded Rust FFI',
              trailing: SettingsMonoChip(text: version ?? 'Loading…'),
            );
          },
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Symbols.menu_book,
          tone: EtTone.info,
          title: 'Documentation',
          subtitle: 'easytier.cn',
          trailing: Icon(Symbols.content_copy, size: 18, color: p.text2),
          onTap: () => _copyLink('https://easytier.cn'),
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Symbols.code,
          tone: EtTone.neutral,
          title: 'Source repository',
          subtitle: 'github.com/EasyTier/EasyTier',
          trailing: Icon(Symbols.content_copy, size: 18, color: p.text2),
          onTap: () => _copyLink('https://github.com/EasyTier/EasyTier'),
        ),
      ],
    );
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $url')),
    );
  }

  Future<void> _openConfigServerSheet(AppState state) async {
    final controller = TextEditingController(text: state.configServerUrl);
    final saved = await showEtSheet<String>(
      context: context,
      builder: (sheetContext) {
        final p = sheetContext.et;
        final text = Theme.of(sheetContext).textTheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            EtSpace.x5,
            EtSpace.x2,
            EtSpace.x5,
            EtSpace.x5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const EtIconBadge(
                    icon: Symbols.cloud_sync,
                    tone: EtTone.info,
                    size: 40,
                  ),
                  const SizedBox(width: EtSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Config server',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: p.text,
                          ),
                        ),
                        Text(
                          'Pull managed network profiles from a self-hosted server',
                          style: text.bodySmall?.copyWith(color: p.text2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: EtSpace.x4),
              EtTextField(
                key: const Key('settings-config-server-input'),
                label: 'Server URL',
                controller: controller,
                hint: 'https://config.example.com',
                mono: true,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: EtSpace.x4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (state.configServerUrl.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(''),
                      child: const Text('Clear'),
                    ),
                  const SizedBox(width: EtSpace.x2),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: EtSpace.x2),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(controller.text.trim()),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (saved != null && mounted) {
      state.setConfigServerUrl(saved);
    }
  }
}
