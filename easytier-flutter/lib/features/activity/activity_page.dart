import 'dart:collection';

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';

/// Activity answers exactly one question: **what changed?**
///
/// Material 3: day-grouped sections inside a Card, each event a `ListTile` with
/// a tonal status circle, title, optional detail and a mono trailing time. The
/// feed is the local one owned by `AppState` (the core keeps its own logs), so
/// it keeps working while the tunnel is down. Long feeds are virtualized;
/// clearing only hides the events collected so far and says so before doing it.
enum _ActivityFilter { all, connection, peers, warnings }

extension on _ActivityFilter {
  String get label => switch (this) {
    _ActivityFilter.all => I18n.t('All'),
    _ActivityFilter.connection => I18n.t('Connection'),
    _ActivityFilter.peers => I18n.t('Peers'),
    _ActivityFilter.warnings => I18n.t('Warnings'),
  };

  bool matches(NetworkEvent event) => switch (this) {
    _ActivityFilter.all => true,
    _ActivityFilter.connection =>
      event.kind == EventKind.connected ||
          event.kind == EventKind.disconnected ||
          event.kind == EventKind.info,
    _ActivityFilter.peers =>
      event.kind == EventKind.peerJoined || event.kind == EventKind.peerLeft,
    _ActivityFilter.warnings =>
      event.kind == EventKind.warning || event.kind == EventKind.error,
  };
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  _ActivityFilter _filter = _ActivityFilter.all;

  /// Events that existed when the user confirmed "Clear". Local-only dismissal:
  /// `AppState.events` is the shell badge's source and stays untouched, so new
  /// events keep arriving and remain visible. Identity set, because the list is
  /// mutated by `AppState` and indices would shift under it.
  final Set<NetworkEvent> _cleared = HashSet<NetworkEvent>.identity();

  void _clearVisible(AppState state) {
    setState(() => _cleared.addAll(state.events));
  }

  Future<void> _confirmClear(BuildContext pageContext, AppState state) async {
    final p = pageContext.et;
    final confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(I18n.t('Clear activity?')),
        content: const Text(
          'This clears the local event timeline on this device only. '
          'The core keeps its own logs, and nothing on the network changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(I18n.t('Cancel')),
          ),
          FilledButton(
            key: const Key('activity-clear-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: p.danger,
              foregroundColor: p.onDanger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(I18n.t('Clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _clearVisible(state);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final all = state.events;

    final visible = <NetworkEvent>[
      for (final event in all)
        if (!_cleared.contains(event)) event,
    ]..sort((a, b) => b.at.compareTo(a.at));
    final filtered = visible.where(_filter.matches).toList();
    final counts = {
      for (final filter in _ActivityFilter.values)
        filter: visible.where(filter.matches).length,
    };
    final entries = _entries(filtered);

    return EtPage(
      title: I18n.t('Activity'),
      subtitle: _subtitle(all.length, visible.length, filtered.length),
      actions: [
        EtIconButton(
          key: const Key('activity-clear'),
          icon: Symbols.delete_outline,
          tooltip: I18n.t('Clear activity'),
          onPressed: visible.isEmpty ? null : () => _confirmClear(context, state),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (visible.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: EtSpace.x3),
              child: _ActivityFilterBar(
                selected: _filter,
                counts: counts,
                onSelect: (next) => setState(() => _filter = next),
              ),
            ),
          Expanded(
            child: _body(
              context,
              visible: visible,
              filtered: filtered,
              entries: entries,
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(int total, int visible, int filtered) {
    if (total == 0) return 'No events yet';
    if (_filter == _ActivityFilter.all) return '$filtered events';
    return '$filtered of $visible events';
  }

  Widget _body(
    BuildContext context, {
    required List<NetworkEvent> visible,
    required List<NetworkEvent> filtered,
    required List<_ActivityEntry> entries,
  }) {
    if (visible.isEmpty) {
      final cleared = _cleared.isNotEmpty;
      return _emptyScroll(
        EtEmptyState(
          icon: cleared ? Symbols.history : Symbols.monitor_heart,
          title: cleared ? I18n.t('Activity cleared') : I18n.t('No activity yet'),
          message: cleared
              ? 'New events appear here as the network changes. The core keeps its own logs.'
              : 'Connect a network and the local timeline starts here. Events stay on this device.',
        ),
      );
    }
    if (filtered.isEmpty) {
      return _emptyScroll(
        EtEmptyState(
          icon: Symbols.filter_list,
          title: switch (_filter) {
            _ActivityFilter.connection => 'No connection events',
            _ActivityFilter.peers => 'No peer events',
            _ActivityFilter.warnings => 'No warnings',
            _ActivityFilter.all => 'No activity',
          },
          message: 'Nothing in ${_plural(visible.length, 'event')} matches this filter.',
          action: EtPrimaryButton(
            label: I18n.t('Show all'),
            icon: Symbols.restart_alt,
            tonal: true,
            expanded: false,
            onPressed: () => setState(() => _filter = _ActivityFilter.all),
          ),
        ),
      );
    }
    return _timeline(context, entries);
  }

  static String _plural(int count, String singular) =>
      count == 1 ? '$count $singular' : '$count ${singular}s';

  Widget _timeline(BuildContext context, List<_ActivityEntry> entries) {
    // Short feeds shrink the Card to their content; long feeds keep the
    // virtualized, full-height list (never build 100+ rows just to measure).
    final shrink = entries.length <= 12;
    final list = ListView.builder(
      key: const PageStorageKey<String>('activity-list'),
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.only(bottom: EtSpace.x2),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final event = entry.event;
        if (event == null) return _DayHeader(label: entry.label!);
        return _EventRow(event: event);
      },
    );
    final surface = EtSurface(padding: EdgeInsets.zero, child: list);
    return shrink ? Align(alignment: Alignment.topCenter, child: surface) : surface;
  }

  /// Flattens day headers and events into one virtualized item list.
  List<_ActivityEntry> _entries(List<NetworkEvent> events) {
    final entries = <_ActivityEntry>[];
    String? currentDay;
    for (final event in events) {
      final day = _dayKey(event.at);
      if (day != currentDay) {
        entries.add(_ActivityEntry.header(_dayLabel(event.at)));
        currentDay = day;
      }
      entries.add(_ActivityEntry.event(event));
    }
    return entries;
  }

  static String _dayKey(DateTime at) => '${at.year}-${at.month}-${at.day}';

  static String _dayLabel(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final delta = today.difference(day).inDays;
    if (delta == 0) return I18n.t('Today');
    if (delta == 1) return I18n.t('Yesterday');
    return '${_months[at.month - 1]} ${at.day}';
  }

  static String _time(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  Widget _emptyScroll(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// One flattened timeline item: a day header or an event.
class _ActivityEntry {
  const _ActivityEntry.header(this.label) : event = null;

  const _ActivityEntry.event(this.event) : label = null;

  final String? label;
  final NetworkEvent? event;
}

/// M3 list-section header: `labelLarge` on `onSurfaceVariant`, divider below.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(EtSpace.x4, EtSpace.x4, EtSpace.x4, EtSpace.x1),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: p.text2),
          ),
        ),
        const Divider(height: 1, indent: EtSpace.x4, endIndent: EtSpace.x4),
      ],
    );
  }
}

/// M3 event row with an expressive leading `EtIconBadge`: the squircle's tone
/// encodes the kind (connected = success, warning = warning, error = danger,
/// info = accent) while the icon shape and the title text carry the same meaning
/// without relying on colour. Timestamp stays mono, right-aligned.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final NetworkEvent event;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final theme = Theme.of(context);
    final (icon, tone) = switch (event.kind) {
      EventKind.connected => (Symbols.check_circle, EtTone.success),
      EventKind.disconnected => (Symbols.link_off, EtTone.danger),
      EventKind.peerJoined => (Symbols.person_add, EtTone.info),
      EventKind.peerLeft => (Symbols.person_remove, EtTone.neutral),
      EventKind.warning => (Symbols.warning, EtTone.warn),
      EventKind.error => (Symbols.error, EtTone.danger),
      EventKind.info => (Symbols.info, EtTone.accent),
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
      leading: ExcludeSemantics(
        child: EtIconBadge(icon: icon, tone: tone, size: 40),
      ),
      title: Text(
        event.title,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: event.detail == null
          ? null
          : Text(
              event.detail!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: p.text2),
            ),
      trailing: Text(
        _ActivityPageState._time(event.at),
        style: EtText.mono(size: EtType.caption, color: p.text2),
      ),
    );
  }
}

class _ActivityFilterBar extends StatelessWidget {
  const _ActivityFilterBar({
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final _ActivityFilter selected;
  final Map<_ActivityFilter, int> counts;
  final ValueChanged<_ActivityFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = context.et.scheme;
    return Wrap(
      spacing: EtSpace.x2,
      runSpacing: EtSpace.x2,
      children: [
        for (final filter in _ActivityFilter.values)
          Material(
            key: Key('activity-filter-${filter.name}'),
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(EtRadius.pill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                EtHaptics.selection();
                onSelect(filter);
              },
              child: AnimatedContainer(
                duration: context.etReducedMotion
                    ? Duration.zero
                    : EtDuration.fast,
                curve: EtCurves.standard,
                padding: const EdgeInsets.symmetric(
                  horizontal: EtSpace.x3,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selected == filter
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(EtRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      filter.label,
                      style: EtText.ui(
                        size: EtType.caption,
                        weight: selected == filter
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected == filter
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${counts[filter] ?? 0}',
                      style: EtText.mono(
                        size: EtType.micro,
                        weight: FontWeight.w600,
                        color: selected == filter
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
