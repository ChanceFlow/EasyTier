import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'peer_detail_sheet.dart';
import 'peer_format.dart';
import 'peer_pills.dart';

/// Devices answers exactly one question: **who is slow?**
///
/// Material 3: a grouped section list of two-line `ListTile`s on compact
/// windows, and a `DataTable` (with sort indicators) on wide ones. Online peers
/// first, offline peers never hidden. Search is an M3 `SearchBar`, sorting is an
/// M3 menu, status is communicated by icon + label + colour together.
enum _DeviceSort { latency, name, status }

extension on _DeviceSort {
  String get label => switch (this) {
    _DeviceSort.latency => 'Latency',
    _DeviceSort.name => 'Name',
    _DeviceSort.status => 'Status',
  };
}

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  _DeviceSort _sort = _DeviceSort.latency;
  bool _searchOpen = false;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _query = '';
      }
    });
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
    _searchFocus.requestFocus();
  }

  void _setSort(_DeviceSort value) => setState(() => _sort = value);

  bool _matches(Peer peer) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return peer.hostname.toLowerCase().contains(query) ||
        peer.ipv4.toLowerCase().contains(query);
  }

  int _compare(Peer a, Peer b) {
    switch (_sort) {
      case _DeviceSort.name:
        return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
      case _DeviceSort.latency:
        return _byLatency(a, b);
      case _DeviceSort.status:
        return _byStatus(a, b);
    }
  }

  static int _byLatency(Peer a, Peer b) {
    final al = a.online ? a.latencyMs : null;
    final bl = b.online ? b.latencyMs : null;
    if (al == null && bl == null) return a.hostname.compareTo(b.hostname);
    if (al == null) return 1;
    if (bl == null) return -1;
    final byLatency = al.compareTo(bl);
    return byLatency == 0 ? a.hostname.compareTo(b.hostname) : byLatency;
  }

  static int _byStatus(Peer a, Peer b) {
    int rank(Peer peer) => switch (peer.path) {
      'direct' => 0,
      'relay' => 1,
      _ => 2,
    };
    final byPath = rank(a).compareTo(rank(b));
    if (byPath != 0) return byPath;
    return _byLatency(a, b);
  }

  String _subtitle(InstanceStatus status) {
    final phase = status.phase;
    if (phase == ConnectionPhase.connecting) return 'Connecting…';
    if (phase == ConnectionPhase.error) return 'Connection failed';
    if (!phase.isUp) return 'Not connected';
    final peers = status.peers;
    final online = peers.where((peer) => peer.online).length;
    return '$online of ${peers.length} online · ${status.routeCount} routes';
  }

  /// Column the M3 table is currently sorted by, for the header sort indicator.
  int? get _sortColumnIndex => switch (_sort) {
    _DeviceSort.status => 0,
    _DeviceSort.name => 1,
    _DeviceSort.latency => 3,
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final status = state.status;
    final desktop = context.etDesktop;
    final up = status.phase.isUp;

    final visible = status.peers.where(_matches).toList();
    final online = [
      for (final peer in visible)
        if (peer.online) peer,
    ]..sort(_compare);
    final offline = [
      for (final peer in visible)
        if (!peer.online) peer,
    ]..sort(_compare);
    final entries = _entries(online, offline);

    return EtPage(
      title: 'Devices',
      subtitle: _subtitle(status),
      actions: [
        _sortButton(),
        EtIconButton(
          key: const Key('devices-search-toggle'),
          icon: _searchOpen ? Symbols.close : Symbols.search,
          tooltip: _searchOpen ? 'Close search' : 'Search devices',
          onPressed: _toggleSearch,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: EtSpace.x3),
              child: _searchBar(),
            ),
          if (up && status.phase == ConnectionPhase.degraded && status.peers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: EtSpace.x3),
              child: const EtBanner(
                title: 'All peers are relayed',
                message: 'No direct path is available right now; latency includes relay hops.',
                tone: EtTone.warn,
              ),
            ),
          if (!up && state.lastError != null && status.phase != ConnectionPhase.connecting)
            Padding(
              padding: const EdgeInsets.only(bottom: EtSpace.x3),
              child: EtBanner(
                title: 'Connection failed',
                message: state.lastError!,
                tone: EtTone.danger,
              ),
            ),
          if (up && status.peers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: EtSpace.x3),
              child: _DevicesSummary(status: status),
            ),
          Expanded(
            child: _body(
              context: context,
              state: state,
              status: status,
              online: online,
              offline: offline,
              entries: entries,
              desktop: desktop,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortButton() {
    return PopupMenuButton<_DeviceSort>(
      key: const Key('devices-sort'),
      tooltip: 'Sort devices',
      icon: const Icon(Symbols.sort),
      onSelected: _setSort,
      itemBuilder: (context) => [
        for (final sort in _DeviceSort.values)
          CheckedPopupMenuItem<_DeviceSort>(
            key: Key('devices-sort-${sort.name}'),
            value: sort,
            checked: _sort == sort,
            child: Text(sort.label),
          ),
      ],
    );
  }

  /// M3 search bar with an expressive primary-tinted surface (still the M3
  /// `SearchBar` widget, fully rounded, leading search icon, inline clear).
  Widget _searchBar() {
    final p = context.et;
    return SearchBar(
      key: const Key('devices-search-field'),
      controller: _searchController,
      focusNode: _searchFocus,
      hintText: 'Filter by hostname or IP',
      leading: const Icon(Symbols.search),
      backgroundColor: WidgetStatePropertyAll<Color?>(
        Color.alphaBlend(
          p.scheme.primary.withValues(alpha: p.isDark ? 0.16 : 0.08),
          p.scheme.surfaceContainerHigh,
        ),
      ),
      trailing: [
        if (_query.isNotEmpty)
          IconButton(
            icon: const Icon(Symbols.close),
            tooltip: 'Clear search',
            onPressed: _clearSearch,
          ),
      ],
      onChanged: (value) => setState(() => _query = value),
      textInputAction: TextInputAction.search,
    );
  }

  Widget _body({
    required BuildContext context,
    required AppState state,
    required InstanceStatus status,
    required List<Peer> online,
    required List<Peer> offline,
    required List<_ListEntry> entries,
    required bool desktop,
  }) {
    final phase = status.phase;
    final message = status.error ?? state.lastError;

    if (phase == ConnectionPhase.connecting) {
      return _emptyScroll(
        const EtEmptyState(
          icon: Symbols.monitor_heart,
          title: 'Connecting…',
          message: 'Devices appear as soon as peers answer on the mesh.',
        ),
      );
    }
    if (!phase.isUp && (phase == ConnectionPhase.error || message != null)) {
      return _emptyScroll(
        EtEmptyState(
          icon: Symbols.report,
          title: 'Could not connect',
          message: message ?? 'The core reported a failure.',
          action: _connectButton(state, label: 'Try again'),
        ),
      );
    }
    if (!phase.isUp) {
      return _emptyScroll(
        EtEmptyState(
          icon: Symbols.devices,
          title: 'Connect to see peers',
          message: 'The full device list appears here once the network is up.',
          action: _connectButton(state, label: 'Connect'),
        ),
      );
    }
    if (status.peers.isEmpty) {
      return _emptyScroll(
        const EtEmptyState(
          icon: Symbols.devices,
          title: 'No peers yet',
          message: 'This device is alone on the network. Peers show up here as they join.',
        ),
      );
    }
    if (online.isEmpty && offline.isEmpty) {
      return _emptyScroll(
        EtEmptyState(
          icon: Symbols.search,
          title: 'No devices match',
          message: 'Nothing matches “${_query.trim()}”. Try a hostname or a virtual IP.',
          action: OutlinedButton.icon(
            onPressed: _clearSearch,
            icon: const Icon(Symbols.close, size: 18),
            label: const Text('Clear search'),
          ),
        ),
      );
    }
    return desktop ? _table(context, entries) : _peerList(entries);
  }

  Widget _connectButton(AppState state, {required String label}) {
    return EtPrimaryButton(
      label: label,
      icon: Symbols.verified_user,
      expanded: false,
      loading: state.busy,
      onPressed: state.busy ? null : state.connect,
    );
  }

  /// Flattens the two groups into one item list so a single virtualized
  /// `ListView.builder` renders headers and rows together (no nested scrollables,
  /// no plain `Column` of rows).
  List<_ListEntry> _entries(List<Peer> online, List<Peer> offline) => [
    if (online.isNotEmpty) _ListEntry.header('Online', online.length),
    for (var i = 0; i < online.length; i++)
      _ListEntry.peer(online[i], firstInGroup: i == 0),
    if (offline.isNotEmpty) _ListEntry.header('Offline', offline.length),
    for (var i = 0; i < offline.length; i++)
      _ListEntry.peer(offline[i], firstInGroup: i == 0),
  ];

  /// Compact window: M3 list inside a Card, section headers in `labelLarge`.
  Widget _peerList(List<_ListEntry> entries) {
    final p = context.et;
    return EtSurface(
      // Inset the rows from the card edge so the avatar and the latency pill
      // read as expressive floating elements, not as a flush data table.
      padding: const EdgeInsets.symmetric(horizontal: EtSpace.x2),
      child: ListView.builder(
        key: const PageStorageKey<String>('devices-phone-list'),
        padding: const EdgeInsets.only(bottom: EtSpace.x2),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final peer = entry.peer;
          if (peer == null) {
            return _GroupHeader(label: entry.label!, count: entry.count);
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!entry.firstInGroup) Divider(height: 1, indent: EtSpace.x2, endIndent: EtSpace.x2, color: p.border),
              EtPeerRow(
                peer: peer,
                onTap: () => showPeerDetailSheet(context, peer),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Wide window: M3 `DataTable` with clickable rows and built-in sort
  /// indicators. The group header is a table row so columns stay aligned by
  /// DataTable itself — the screen no longer owns any column geometry.
  Widget _table(BuildContext context, List<_ListEntry> entries) {
    final theme = Theme.of(context);
    final p = context.et;
    final rows = <DataRow>[];

    for (final entry in entries) {
      final peer = entry.peer;
      if (peer == null) {
        rows.add(
          DataRow(
            color: WidgetStatePropertyAll<Color?>(p.surface2),
            cells: [
              const DataCell(SizedBox.shrink()),
              DataCell(
                Text(
                  '${entry.label} · ${entry.count}',
                  style: theme.textTheme.labelLarge?.copyWith(color: p.text2),
                ),
              ),
              const DataCell(SizedBox.shrink()),
              const DataCell(SizedBox.shrink()),
            ],
          ),
        );
        continue;
      }
      rows.add(
        DataRow(
          onSelectChanged: (_) => showPeerDetailSheet(context, peer),
          cells: [
            DataCell(_StatusCell(peer: peer)),
            DataCell(_DeviceCell(peer: peer)),
            DataCell(_PathCell(peer: peer)),
            DataCell(
              SizedBox(
                width: 96,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: LatencyPill(peer: peer),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return EtSurface(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        child: DataTable(
          sortColumnIndex: _sortColumnIndex,
          sortAscending: true,
          showCheckboxColumn: false,
          horizontalMargin: EtSpace.x4,
          columnSpacing: EtSpace.x6,
          headingRowHeight: 48,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 72,
          headingTextStyle: theme.textTheme.labelLarge?.copyWith(color: p.text2),
          dataTextStyle: theme.textTheme.bodyMedium?.copyWith(color: p.text),
          columns: [
            DataColumn(
              label: const Text('Status'),
              onSort: (_, _) => _setSort(_DeviceSort.status),
            ),
            DataColumn(
              label: const Text('Device'),
              onSort: (_, _) => _setSort(_DeviceSort.name),
            ),
            const DataColumn(label: Text('Path')),
            DataColumn(
              label: const Text('Latency'),
              numeric: true,
              onSort: (_, _) => _setSort(_DeviceSort.latency),
            ),
          ],
          rows: rows,
        ),
      ),
    );
  }

  /// Empty states can be taller than a landscape phone; keeping them scrollable
  /// avoids a hard overflow instead of clipping the call to action.
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

/// One flattened list item: a group header or a peer row.
class _ListEntry {
  const _ListEntry.header(this.label, this.count)
      : peer = null,
        firstInGroup = false;

  const _ListEntry.peer(this.peer, {required this.firstInGroup})
      : label = null,
        count = 0;

  final String? label;
  final int count;
  final Peer? peer;
  final bool firstInGroup;
}

/// M3 list-section header: `labelLarge` on `onSurfaceVariant`, 16dp inset.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Padding(
      padding: const EdgeInsets.fromLTRB(EtSpace.x4, EtSpace.x4, EtSpace.x4, EtSpace.x1),
      child: Text(
        '$label · $count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: p.text2),
      ),
    );
  }
}

/// Status cell of the desktop table: icon (filled/outline) + label.
class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context) {
    return EtBadge(
      label: peerStatusLabel(peer),
      tone: latencyTone(peer),
      icon: peer.online ? Symbols.circle : Symbols.radio_button_unchecked,
    );
  }
}

/// Device cell of the desktop table: hostname (+ offline chip) over the IP.
class _DeviceCell extends StatelessWidget {
  const _DeviceCell({required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: EtAvatar(name: peer.hostname, size: 32)),
        const SizedBox(width: EtSpace.x3),
        SizedBox(
          width: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      peer.hostname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EtText.ui(
                        size: EtType.bodySm,
                        weight: FontWeight.w500,
                        color: peer.online ? p.text : p.text2,
                      ),
                    ),
                  ),
                  if (!peer.online) ...[
                    const SizedBox(width: EtSpace.x2),
                    EtBadge(
                      label: peer.lastSeen == null
                          ? 'offline'
                          : 'offline ${peerLastSeenLabel(peer).replaceAll(' ago', '')}',
                      tone: EtTone.neutral,
                    ),
                  ],
                ],
              ),
              Text(
                peer.ipv4,
                style: EtText.mono(size: EtType.caption, color: p.text2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Path cell: relay paths are an M3 tonal chip, direct paths are plain text.
class _PathCell extends StatelessWidget {
  const _PathCell({required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    if (!peer.online) {
      return Text('—', style: EtText.ui(size: EtType.caption, color: p.textDisabled));
    }
    if (peer.path == 'relay') {
      return const EtBadge(label: 'Relay', tone: EtTone.warn, icon: Symbols.alt_route);
    }
    return Text(peer.pathLabel, style: EtText.ui(size: EtType.caption, color: p.text2));
  }
}

/// Expressive status summary: online / offline / routes as tonal chips. `Wrap`
/// keeps it overflow-free at 320dp (chips flow to a second line instead of
/// clipping) and adds no scrollable, so list scroll positions stay unaffected.
class _DevicesSummary extends StatelessWidget {
  const _DevicesSummary({required this.status});

  final InstanceStatus status;

  @override
  Widget build(BuildContext context) {
    final online = status.peers.where((peer) => peer.online).length;
    final offline = status.peers.length - online;
    return Wrap(
      spacing: EtSpace.x2,
      runSpacing: EtSpace.x2,
      children: [
        _SummaryChip(
          icon: Symbols.check_circle,
          label: '$online online',
          tone: EtTone.success,
        ),
        _SummaryChip(
          icon: Symbols.radio_button_unchecked,
          label: '$offline offline',
          tone: EtTone.neutral,
        ),
        _SummaryChip(
          icon: Symbols.alt_route,
          label: '${status.routeCount} routes',
          tone: EtTone.tertiary,
        ),
      ],
    );
  }
}

/// Expressive stadium chip: tonal container, icon, quiet label.
class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label, required this.tone});

  final IconData icon;
  final String label;
  final EtTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final (bg, fg) = tone.resolve(p);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EtSpace.x3, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(EtRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: EtSpace.x2),
          Text(
            label,
            style: EtText.ui(
              size: EtType.caption,
              weight: FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

