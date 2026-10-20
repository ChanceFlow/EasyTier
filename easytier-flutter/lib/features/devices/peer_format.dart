import '../../core/models/models.dart';

/// Presentation rules shared by the phone row, the desktop table, the detail
/// sheet and the tonal latency pills — so they never disagree about a machine
/// value or a relative time.

/// Machine-readable latency cell. Offline / unknown is an em dash, not "0 ms".
String peerLatencyLabel(Peer peer) {
  final latency = peer.latencyMs;
  if (!peer.online || latency == null) return '—';
  return '$latency ms';
}

String peerStatusLabel(Peer peer) => peer.online ? 'Online' : 'Offline';

/// Relative last-seen text for the detail sheet. The table row keeps the short
/// form ("offline 12m") and the sheet spells it out ("12m ago").
String peerLastSeenLabel(Peer peer, {DateTime? now}) {
  final lastSeen = peer.lastSeen;
  if (lastSeen == null) return peer.online ? 'Online now' : 'Unknown';
  final delta = (now ?? DateTime.now()).difference(lastSeen);
  if (delta.inSeconds < 45) return 'Just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}
