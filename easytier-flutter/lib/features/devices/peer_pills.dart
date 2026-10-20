import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'peer_format.dart';

/// Expressive latency treatment shared by the phone rows, the desktop table and
/// the detail sheet.
///
/// Tone ladder: offline → neutral, relayed → warning, slow (>90 ms) → error,
/// otherwise success. The number itself stays in the platform mono font, and the
/// row still says "offline"/"Relay via …" in text, so colour is never the only
/// carrier of state.
EtTone latencyTone(Peer peer) {
  if (!peer.online) return EtTone.neutral;
  if (peer.path == 'relay') return EtTone.warn;
  final latency = peer.latencyMs;
  if (latency == null) return EtTone.neutral;
  return latency > 90 ? EtTone.danger : EtTone.success;
}

/// Visible tonal pill: mono number on an M3 container, stadium shape.
class LatencyPill extends StatelessWidget {
  const LatencyPill({super.key, required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final (bg, fg) = latencyTone(peer).resolve(p);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EtSpace.x2, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(EtRadius.pill),
      ),
      child: Text(
        peerLatencyLabel(peer),
        style: EtText.mono(
          size: EtType.caption,
          weight: FontWeight.w500,
          color: fg,
          height: 1.3,
        ),
      ),
    );
  }
}
