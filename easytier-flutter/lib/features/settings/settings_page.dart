import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'logs_page.dart';
import 'settings_widgets.dart';

const _appVersion = '2.6.4+9';
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
      title: I18n.t('Settings'),
      subtitle: I18n.t('Preferences & core runtime'),
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
      title: I18n.t('Appearance'),
      children: [
        SettingsSegmentedRow<ThemeMode>(
          icon: Symbols.palette,
          tone: EtTone.accent,
          title: I18n.t('Theme'),
          value: state.themeMode,
          options: [
            (ThemeMode.dark, I18n.t('Dark')),
            (ThemeMode.light, I18n.t('Light')),
            (ThemeMode.system, I18n.t('System')),
          ],
          onChanged: state.setThemeMode,
        ),
        const SettingsDivider(),
        SettingsSegmentedRow<Locale>(
          icon: Symbols.language,
          tone: EtTone.info,
          title: I18n.t('Language'),
          value: state.locale,
          options: [
            (Locale('en'), I18n.t('English')),
            (Locale('zh'), I18n.t('中文')),
          ],
          onChanged: state.setLocale,
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Symbols.animation,
          tone: EtTone.tertiary,
          title: I18n.t('Reduced motion'),
          subtitle: I18n.t('System accessibility'),
          trailing: EtBadge(
            label: reduced ? I18n.t('Reduced') : I18n.t('Standard'),
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
      title: I18n.t('Core & Networking'),
      children: [
        SettingsRow(
          icon: Symbols.memory,
          tone: EtTone.success,
          title: I18n.t('Execution mode'),
          subtitle: I18n.t('In-process FFI tunnel'),
          trailing: EtBadge(
            label: I18n.t('Normal (in-process)'),
            tone: EtTone.success,
          ),
        ),
        const SettingsDivider(),
        SettingsRow(
          key: const Key('settings-config-server-row'),
          icon: Symbols.cloud_sync,
          tone: EtTone.info,
          title: I18n.t('Config server'),
          subtitle: hasServer
              ? state.configServerUrl
              : I18n.t('Remote profile sync'),
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
                  label: hasServer ? I18n.t('Configured') : I18n.t('Off'),
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
            title: I18n.t('Log level'),
            subtitle: I18n.t('Core event verbosity'),
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
          title: I18n.t('Client logs'),
          subtitle: I18n.t('Lifecycle, RPC and config lines'),
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
      title: I18n.t('About'),
      children: [
        SettingsRow(
          icon: Symbols.verified_user,
          tone: EtTone.accent,
          title: I18n.t('App version'),
          subtitle: I18n.t('Flutter client'),
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
              title: I18n.t('Core version'),
              subtitle: I18n.t('Embedded Rust FFI'),
              trailing: SettingsMonoChip(text: version ?? 'Loading…'),
            );
          },
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Symbols.menu_book,
          tone: EtTone.info,
          title: I18n.t('Documentation'),
          subtitle: 'easytier.cn',
          trailing: Icon(Symbols.content_copy, size: 18, color: p.text2),
          onTap: () => _copyLink('https://easytier.cn'),
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Symbols.code,
          tone: EtTone.neutral,
          title: I18n.t('Source repository'),
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
                          I18n.t('Config server'),
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
                      child: Text(I18n.t('Clear')),
                    ),
                  const SizedBox(width: EtSpace.x2),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(I18n.t('Cancel')),
                  ),
                  const SizedBox(width: EtSpace.x2),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(controller.text.trim()),
                    child: Text(I18n.t('Save')),
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
