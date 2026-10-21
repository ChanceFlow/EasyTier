import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import 'package:flutter/services.dart';

import '../../core/models/models.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'toml_source.dart';

/// Full-screen editor for the network configuration as TOML source.
///
/// This is a real source-file workflow, not a read-only preview: the text is
/// parsed locally, validated, and the result is applied back to the form draft
/// (the user still presses Save before anything reaches the core). Unknown keys
/// are tolerated and listed as warnings; syntax errors block Apply and name the
/// offending line.
class SourceEditorPage extends StatefulWidget {
  const SourceEditorPage({super.key, required this.initial});

  final NetworkConfig initial;

  @override
  State<SourceEditorPage> createState() => _SourceEditorPageState();
}

class _SourceEditorPageState extends State<SourceEditorPage> {
  late final TextEditingController _controller;
  late TomlParseResult _result;

  String get _source => _controller.text;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: networkConfigToToml(widget.initial));
    _result = parseNetworkConfigToml(_controller.text, base: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reparse(String _) {
    setState(() {
      _result = parseNetworkConfigToml(_source, base: widget.initial);
    });
  }

  void _revert() {
    setState(() {
      _controller.text = networkConfigToToml(widget.initial);
      _result = parseNetworkConfigToml(_controller.text, base: widget.initial);
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
    EtHaptics.selection();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _source));
    if (!mounted) return;
    EtHaptics.selection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(I18n.t('Source copied to clipboard.'))),
    );
  }

  /// Copies the source and, on desktop, also writes it to ~/Downloads so the
  /// file can be edited/shared like a real config file.
  Future<void> _export() async {
    final text = _source;
    await Clipboard.setData(ClipboardData(text: text));
    String? savedPath;
    if (!kIsWeb &&
        !Platform.environment.containsKey('FLUTTER_TEST') &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      try {
        final home =
            Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
        if (home != null) {
          final dir = Directory('$home/Downloads');
          await dir.create(recursive: true);
          final file = File(
            '${dir.path}/easytier-${widget.initial.instanceName}.toml',
          );
          await file.writeAsString(text);
          savedPath = file.path;
        }
      } catch (_) {
        // File system unavailable: the clipboard copy above still succeeded.
      }
    }
    if (!mounted) return;
    EtHaptics.selection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          savedPath == null
              ? I18n.t('Source copied to clipboard.')
              : 'Saved to $savedPath (also copied).',
        ),
      ),
    );
  }

  Future<void> _import() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.t('Clipboard is empty.'))),
      );
      return;
    }
    setState(() {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
      _result = parseNetworkConfigToml(text, base: widget.initial);
    });
    EtHaptics.selection();
  }

  void _apply() {
    final config = _result.config;
    if (config == null) return;
    EtHaptics.selection();
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final scheme = p.scheme;
    final theme = Theme.of(context);
    final reduced = context.etReducedMotion;
    final errors = _result.errors;
    final warnings = _result.warnings;
    final lineCount = _source.isEmpty ? 1 : '\n'.allMatches(_source).length + 1;

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              I18n.t('Edit source'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              '${widget.initial.networkName} · TOML',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EtText.ui(size: EtType.caption, color: p.text2),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('source-import'),
            tooltip: I18n.t('Import from clipboard'),
            onPressed: _import,
            icon: const Icon(Symbols.upload_file),
          ),
          IconButton(
            key: const Key('source-export'),
            tooltip: I18n.t('Export (copy + save file)'),
            onPressed: _export,
            icon: const Icon(Symbols.download),
          ),
          IconButton(
            tooltip: I18n.t('Copy source'),
            onPressed: _copy,
            icon: const Icon(Symbols.content_copy),
          ),
          IconButton(
            tooltip: I18n.t('Revert to current draft'),
            onPressed: _revert,
            icon: const Icon(Symbols.restart_alt),
          ),
          const SizedBox(width: EtSpace.x1),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (errors.isNotEmpty)
            _SourceBanner(
              tone: EtTone.danger,
              icon: Symbols.error,
              title: 'Line ${errors.first.line}: ${errors.first.message}',
              message: errors.length == 1
                  ? 'Fix the syntax error to apply this source.'
                  : '${errors.length} problems — first at line ${errors.first.line}.',
            )
          else if (warnings.isNotEmpty)
            _SourceBanner(
              tone: EtTone.warn,
              icon: Symbols.warning,
              title: '${warnings.length} unknown key${warnings.length == 1 ? '' : 's'} ignored',
              message:
                  'Line ${warnings.first.line}: ${warnings.first.message} Everything else parsed cleanly.',
            )
          else
            _SourceBanner(
              tone: EtTone.success,
              icon: Symbols.check_circle,
              title: I18n.t('Valid TOML'),
              message: 'Applied to the draft only; press Save in Config to persist.',
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                EtSpace.x4,
                EtSpace.x2,
                EtSpace.x4,
                EtSpace.x2,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.sunken,
                  borderRadius: BorderRadius.circular(EtRadius.card),
                  border: Border.all(color: p.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(EtRadius.card),
                  child: TextField(
                    key: const Key('source-editor-field'),
                    controller: _controller,
                    onChanged: _reparse,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    style: EtText.mono(
                      size: 12.5,
                      height: 1.55,
                      color: scheme.onSurface,
                    ),
                    cursorColor: p.accent,
                    decoration: InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(EtSpace.x4),
                      hintText: '# EasyTier network configuration',
                      hintStyle: EtText.mono(
                        size: 12.5,
                        height: 1.55,
                        color: p.textDisabled,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _SourceActionBar(
            lineCount: lineCount,
            errors: errors.length,
            warnings: warnings.length,
            onCancel: () => Navigator.of(context).pop(),
            onApply: _result.ok ? _apply : null,
            reduced: reduced,
          ),
        ],
      ),
    );
  }
}

class _SourceBanner extends StatelessWidget {
  const _SourceBanner({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
  });

  final EtTone tone;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EtSpace.x4,
        EtSpace.x2,
        EtSpace.x4,
        0,
      ),
      child: EtBanner(
        tone: tone,
        icon: icon,
        title: title,
        message: message,
      ),
    );
  }
}

class _SourceActionBar extends StatelessWidget {
  const _SourceActionBar({
    required this.lineCount,
    required this.errors,
    required this.warnings,
    required this.onCancel,
    required this.onApply,
    required this.reduced,
  });

  final int lineCount;
  final int errors;
  final int warnings;
  final VoidCallback onCancel;
  final VoidCallback? onApply;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = context.et;
    final status = errors > 0
        ? '$errors error${errors == 1 ? '' : 's'} · $lineCount lines'
        : warnings > 0
        ? '$warnings warning${warnings == 1 ? '' : 's'} · $lineCount lines'
        : 'Ready · $lineCount lines';

    return Material(
      elevation: 3,
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: EtSpace.x4,
            vertical: EtSpace.x2,
          ),
          child: Row(
            children: [
              Icon(
                errors > 0 ? Symbols.error : Symbols.code,
                size: 16,
                color: errors > 0 ? p.danger : p.text2,
              ),
              const SizedBox(width: EtSpace.x2),
              Expanded(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(color: p.text2),
                ),
              ),
              TextButton(
                onPressed: onCancel,
                child: Text(I18n.t('Cancel')),
              ),
              const SizedBox(width: EtSpace.x2),
              FilledButton(
                key: const Key('source-editor-apply'),
                onPressed: onApply,
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: EtSpace.x5),
                ),
                child: Text(I18n.t('Apply')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
