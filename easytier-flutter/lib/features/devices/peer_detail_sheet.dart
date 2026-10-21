import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import 'package:flutter/services.dart';

import '../../core/models/models.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'peer_format.dart';
import 'peer_pills.dart';

/// Peer detail: the one place that answers "is this device healthy?" for a
/// single node — identity, address, path, latency, last seen.
///
/// Material 3 bottom sheet: a header `ListTile`, a divider, plain `ListTile`
/// fact rows, and a `FilledButton` for the copy action. Copying writes the IPv4
/// to the OS clipboard and confirms with a SnackBar after the sheet closes (the
/// SnackBar lives on the page scaffold, so the sheet must not cover it).
Future<void> showPeerDetailSheet(BuildContext context, Peer peer) {
  return showEtSheet<void>(
    context: context,
    builder: (_) => _PeerDetailSheet(peer: peer),
  );
}

Future<void> _copyIp(BuildContext context, Peer peer) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  EtHaptics.selection();
  await Clipboard.setData(ClipboardData(text: peer.ipv4));
  if (!context.mounted) return;
  navigator.maybePop();
  messenger.showSnackBar(
    SnackBar(content: Text('Copied ${peer.ipv4}')),
  );
}

class _PeerDetailSheet extends StatelessWidget {
  const _PeerDetailSheet({required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final theme = Theme.of(context);
    final pathValue = peer.online ? peer.pathLabel : '—';
    final lastSeen = peerLastSeenLabel(peer);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: EtSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: EtSpace.x6),
              leading: ExcludeSemantics(
                child: EtAvatar(name: peer.hostname, size: 48),
              ),
              title: Text(peer.hostname, style: theme.textTheme.titleLarge),
              subtitle: Text(
                peer.ipv4,
                style: EtText.mono(size: EtType.bodySm, color: p.text2),
              ),
              trailing: EtBadge(
                label: peerStatusLabel(peer),
                tone: peer.online ? EtTone.success : EtTone.neutral,
                icon: peer.online ? Symbols.check_circle : Symbols.radio_button_unchecked,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Symbols.alt_route),
              title: Text(I18n.t('Path')),
              trailing: peer.online && peer.path == 'relay'
                  ? EtBadge(label: peer.pathLabel, tone: EtTone.warn)
                  : Text(pathValue, style: EtText.ui(size: EtType.bodySm, color: p.text)),
            ),
            ListTile(
              leading: const Icon(Symbols.speed),
              title: Text(I18n.t('Latency')),
              trailing: LatencyPill(peer: peer),
            ),
            ListTile(
              leading: const Icon(Symbols.schedule),
              title: Text(I18n.t('Last seen')),
              trailing: Text(
                lastSeen,
                style: EtText.mono(size: EtType.bodySm, color: p.text2),
              ),
            ),
            ListTile(
              leading: const Icon(Symbols.fingerprint),
              title: Text(I18n.t('Peer ID')),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  peer.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: EtText.mono(size: EtType.caption, color: p.text2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(EtSpace.x6, EtSpace.x4, EtSpace.x6, 0),
              child: EtPrimaryButton(
                label: I18n.t('Copy IP'),
                icon: Symbols.content_copy,
                onPressed: () => _copyIp(context, peer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
