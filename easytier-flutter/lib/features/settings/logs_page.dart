import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_state.dart';
import '../../core/state/log_bus.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';

enum _LogFilter { all, info, warn, error }

extension on _LogFilter {
  String get label => switch (this) {
    _LogFilter.all => 'All',
    _LogFilter.info => 'Info+',
    _LogFilter.warn => 'Warnings',
    _LogFilter.error => 'Errors',
  };

  bool matches(LogLevel level) => switch (this) {
    _LogFilter.all => true,
    _LogFilter.info => level.index >= LogLevel.info.index,
    _LogFilter.warn => level.index >= LogLevel.warn.index,
    _LogFilter.error => level.index >= LogLevel.error.index,
  };
}

/// Client-side log viewer. Lines come from the Dart layer (lifecycle, RPC,
/// config writes, events) — the Rust core has no log stream over the FFI seam,
/// so this is labelled "Client logs" rather than pretending to be kernel logs.
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  _LogFilter _filter = _LogFilter.all;

  Future<void> _copy(AppState state) async {
    await Clipboard.setData(ClipboardData(text: state.logs.exportText()));
    if (!mounted) return;
    EtHaptics.selection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${state.logs.entries.length} log lines.')),
    );
  }

  void _clear(AppState state) {
    state.logs.clear();
    EtHaptics.impact();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = context.et;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Client logs',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              'This device · Dart layer',
              style: EtText.ui(size: EtType.caption, color: p.text2),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('logs-copy'),
            tooltip: 'Copy logs',
            onPressed: () => _copy(state),
            icon: const Icon(Symbols.content_copy),
          ),
          IconButton(
            key: const Key('logs-clear'),
            tooltip: 'Clear logs',
            onPressed: () => _clear(state),
            icon: const Icon(Symbols.delete_sweep),
          ),
          const SizedBox(width: EtSpace.x1),
        ],
      ),
      body: ListenableBuilder(
        listenable: state.logs,
        builder: (context, _) {
          final entries = state.logs.entries
              .where((entry) => _filter.matches(entry.level))
              .toList(growable: false);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  EtSpace.x4,
                  EtSpace.x1,
                  EtSpace.x4,
                  EtSpace.x2,
                ),
                child: Wrap(
                  spacing: EtSpace.x2,
                  runSpacing: EtSpace.x2,
                  children: [
                    for (final filter in _LogFilter.values)
                      _LogFilterPill(
                        key: Key('logs-filter-${filter.name}'),
                        label: filter.label,
                        selected: _filter == filter,
                        onTap: () => setState(() => _filter = filter),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const EtEmptyState(
                        icon: Symbols.receipt_long,
                        title: 'No logs yet',
                        message:
                            'Connect a network or save a config and lifecycle lines appear here. Log level is set in Settings.',
                      )
                    : EtSurface(
                        padding: EdgeInsets.zero,
                        child: ListView.separated(
                          key: const PageStorageKey<String>('logs-list'),
                          padding: const EdgeInsets.symmetric(
                            vertical: EtSpace.x1,
                          ),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: EtSpace.x4,
                            endIndent: EtSpace.x4,
                            color: p.border.withValues(alpha: 0.5),
                          ),
                          itemBuilder: (context, index) =>
                              _LogRow(entry: entries[index]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LogFilterPill extends StatelessWidget {
  const _LogFilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final scheme = p.scheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(EtRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          EtHaptics.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: context.etReducedMotion ? Duration.zero : EtDuration.fast,
          curve: EtCurves.standard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(EtRadius.pill),
          ),
          child: Text(
            label,
            style: EtText.ui(
              size: EtType.caption,
              weight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final theme = Theme.of(context);
    final (bg, fg) = switch (entry.level) {
      LogLevel.error => (p.dangerQuiet, p.dangerOnTint),
      LogLevel.warn => (p.warnQuiet, p.warnOnTint),
      LogLevel.info => (p.infoQuiet, p.infoOnTint),
      LogLevel.debug => (p.neutralQuiet, p.text2),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EtSpace.x4,
        EtSpace.x2,
        EtSpace.x4,
        EtSpace.x2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.timeLabel,
            style: EtText.mono(size: EtType.micro, color: p.text3),
          ),
          const SizedBox(width: EtSpace.x2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.level.label,
              style: EtText.mono(
                size: 9.5,
                weight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
          const SizedBox(width: EtSpace.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: p.text,
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
                Text(
                  entry.source,
                  style: EtText.mono(size: 9.5, color: p.text3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
