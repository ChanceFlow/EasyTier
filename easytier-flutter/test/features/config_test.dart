import 'package:easytier_flutter/app.dart';
import 'package:easytier_flutter/core/client/core_client.dart';
import 'package:easytier_flutter/core/models/models.dart';
import 'package:easytier_flutter/core/state/app_state.dart';
import 'package:easytier_flutter/core/ui/ui.dart';
import 'package:easytier_flutter/features/config/config_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

// Other destinations stay mounted inside the shell's IndexedStack, so every
// finder that targets config content is scoped to the ConfigPage subtree.
Finder inConfig(Finder matching) =>
    find.descendant(of: find.byType(ConfigPage), matching: matching);

Finder field(String name) => find.byKey(Key('config-field-$name'));

Finder switchFor(String name) => find.descendant(
  of: find.byKey(Key('config-switch-$name')),
  matching: find.byType(Switch),
);

Finder configSections() => inConfig(find.byType(EtSection));

void main() {
  setUpAll(loadEtFonts);

  testWidgets('four M3 sections, only Basic open, fields keep a single label', (
    tester,
  ) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);

    expect(configSections(), findsNWidgets(4));
    for (final title in ['Basic', 'Advanced', 'Port forward', 'ACL']) {
      expect(inConfig(find.text(title)), findsOneWidget,
          reason: '$title section missing');
    }

    // Basic is expanded; the three expert sections are collapsed, so their
    // children are not built (one disclosure level only).
    expect(field('instance-name'), findsOneWidget);
    expect(field('hostname'), findsOneWidget);
    expect(field('network-name'), findsOneWidget);
    expect(field('network-secret'), findsOneWidget);
    expect(field('peer-urls'), findsOneWidget);
    expect(field('listener-urls'), findsOneWidget);
    expect(field('mtu'), findsNothing);
    expect(field('proxy-cidrs'), findsNothing);
    expect(inConfig(find.textContaining('Rules run top to bottom')), findsNothing);

    // Regression for the golden bug: the M3 floating label owns the label.
    // A second external label would make these finders match twice.
    expect(inConfig(find.text('Instance name')), findsOneWidget);
    expect(inConfig(find.text('Hostname')), findsOneWidget);
    expect(inConfig(find.text('Network name')), findsOneWidget);
    expect(inConfig(find.text('Network secret')), findsOneWidget);

    expect(inConfig(find.text('Unsaved changes')), findsNothing);
    expect(inConfig(find.text('All changes saved')), findsOneWidget);
  });

  testWidgets('bottom action bar is an M3 surface anchored below the form', (
    tester,
  ) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);

    final barFinder = find.byKey(const Key('config-bottom-bar'));
    expect(barFinder, findsOneWidget);

    // M3 bottom action bar: surfaceContainer at elevation 3.
    final bar = tester.widget<Material>(barFinder);
    expect(bar.elevation, 3);
    expect(bar.color, Theme.of(tester.element(barFinder)).colorScheme.surfaceContainer);

    // Regression for the golden bug: the bar is a sibling below the scroll
    // body, never painting over a field.
    final scrollBody = inConfig(find.byType(EtScrollBody));
    expect(scrollBody, findsOneWidget);
    final barRect = tester.getRect(barFinder);
    final scrollRect = tester.getRect(scrollBody);
    expect(barRect.top, moreOrLessEquals(scrollRect.bottom, epsilon: 0.5));

    // The scroll body keeps a bottom gutter at least as tall as the bar.
    final scrollView = tester.widget<SingleChildScrollView>(
      find.descendant(of: scrollBody, matching: find.byType(SingleChildScrollView)),
    );
    final padding = scrollView.padding! as EdgeInsets;
    expect(padding.bottom, greaterThanOrEqualTo(barRect.height));

    expect(
      find.descendant(of: barFinder, matching: find.text('Run with these settings')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: barFinder, matching: find.byType(FilledButton)),
      findsOneWidget,
    );
  });

  testWidgets('editing is dirty, DHCP toggles the static address, save persists', (
    tester,
  ) async {
    final state = await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);

    expect(inConfig(find.text('Unsaved changes')), findsNothing);

    await tester.enterText(field('network-name'), 'EasyTier Lab');
    await pumpFrames(tester);
    expect(inConfig(find.text('Unsaved changes')), findsOneWidget);
    expect(inConfig(find.text('Reset')), findsOneWidget);
    expect(inConfig(find.text('Save')), findsOneWidget);

    // Static addressing only exists when DHCP is off.
    expect(field('virtual-ipv4'), findsNothing);
    await tester.ensureVisible(switchFor('dhcp'));
    await pumpFrames(tester);
    await tester.tap(switchFor('dhcp'));
    await pumpFrames(tester, frames: 12);
    expect(field('virtual-ipv4'), findsOneWidget);
    expect(field('prefix-length'), findsOneWidget);
    // The select keeps one floating label; no external label above the box.
    expect(inConfig(find.text('Prefix length')), findsOneWidget);

    await tester.ensureVisible(switchFor('dhcp'));
    await pumpFrames(tester);
    await tester.tap(switchFor('dhcp'));
    await pumpFrames(tester, frames: 12);
    expect(field('virtual-ipv4'), findsNothing);

    await tester.tap(inConfig(find.text('Save')));
    await pumpFrames(tester);

    expect(inConfig(find.text('Unsaved changes')), findsNothing);
    expect(state.activeConfig?.networkName, 'EasyTier Lab');
    expect(state.instances.single.config.networkName, 'EasyTier Lab');
  });

  testWidgets('invalid submit raises a specific summary and keeps field errors', (
    tester,
  ) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);

    await tester.enterText(field('network-name'), '');
    await pumpFrames(tester);
    await tester.tap(inConfig(find.text('Save')));
    await pumpFrames(tester);

    expect(inConfig(find.text('1 field needs attention')), findsOneWidget);
    expect(inConfig(find.textContaining('Network name is required')), findsWidgets);
    // The summary stays up: the field is still invalid.
    expect(inConfig(find.text('Unsaved changes')), findsOneWidget);
  });

  testWidgets('a bad peer URL names the offending line and segment', (
    tester,
  ) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);

    await tester.enterText(field('peer-urls'), 'tcp://example.com:70000');
    await pumpFrames(tester);
    await tester.tap(inConfig(find.text('Save')));
    await pumpFrames(tester);

    expect(
      inConfig(find.textContaining('Line 1: port “70000” is outside 1–65535')),
      findsWidgets,
    );
  });

  testWidgets('Advanced expands in place, still one disclosure level', (
    tester,
  ) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);

    await tester.ensureVisible(inConfig(find.text('Advanced')));
    await tester.tap(inConfig(find.text('Advanced')));
    await pumpFrames(tester, frames: 12);

    expect(field('mtu'), findsOneWidget);
    expect(field('dev-name'), findsOneWidget);
    expect(field('instance-name'), findsOneWidget);
    // Subheads are M3 captions, not a second disclosure control.
    expect(inConfig(find.text('Transport')), findsOneWidget);
    expect(inConfig(find.text('TRANSPORT')), findsNothing);
  });

  testWidgets('source editor applies edited TOML back to the draft', (tester) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);

    await tester.tap(find.byTooltip('Edit TOML source'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Edit source'), findsOneWidget);
    final editorField = find.byKey(const Key('source-editor-field'));
    expect(editorField, findsOneWidget);
    final editor = tester.widget<TextField>(editorField);
    expect(editor.controller!.text, contains('[network_identity]'));
    expect(editor.controller!.text, contains('instance_id ='));

    await tester.enterText(
      editorField,
      'instance_name = "office-mesh"\nhostname = "renamed-host"\n[network_identity]\nnetwork_name = "Renamed Net"\n',
    );
    await pumpFrames(tester, frames: 12);
    expect(find.textContaining('Valid TOML'), findsOneWidget);

    final applyButton = tester.widget<FilledButton>(
      find.byKey(const Key('source-editor-apply')),
    );
    expect(applyButton.onPressed, isNotNull, reason: 'Apply must be enabled for valid TOML');
    await tester.tap(find.byKey(const Key('source-editor-apply')));
    await pumpFrames(tester, frames: 36);

    expect(find.text('Edit source'), findsNothing);
    expect(find.text('Unsaved changes'), findsOneWidget);
    final name = tester.widget<TextField>(find.descendant(of: field('network-name'), matching: find.byType(TextField)));
    expect(name.controller!.text, 'Renamed Net');
    expect(find.text('Renamed Net'), findsOneWidget);
  });

  testWidgets('source editor blocks Apply on syntax errors', (tester) async {
    await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);

    await tester.tap(find.byTooltip('Edit TOML source'));
    await pumpFrames(tester, frames: 12);

    final editorField = find.byKey(const Key('source-editor-field'));
    await tester.enterText(editorField, 'mtu = not-a-number\n');
    await pumpFrames(tester, frames: 12);

    expect(find.textContaining('Line 1:'), findsOneWidget);
    final apply = tester.widget<FilledButton>(
      find.byKey(const Key('source-editor-apply')),
    );
    expect(apply.onPressed, isNull);
  });

  testWidgets('wide screens pair fields in two columns', (tester) async {
    await pumpDesktopApp(tester, connect: false);
    await openDestination(tester, EtDestination.config);

    final name = tester.getTopLeft(field('network-name'));
    final secret = tester.getTopLeft(field('network-secret'));
    expect(name.dy, moreOrLessEquals(secret.dy, epsilon: 0.5));
    expect(secret.dx, greaterThan(name.dx));
  });

  testWidgets('320 px wide phone does not overflow horizontally', (
    tester,
  ) async {
    await pumpPhoneApp(tester, size: const Size(320, 700), connect: false);
    await openDestination(tester, EtDestination.config);

    expect(tester.takeException(), isNull);
    await tester.enterText(field('network-name'), 'A longer network name');
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no network shows the empty state with a create action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844) * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final state = AppState(client: _EmptyCoreClient(), pollInterval: null);
    addTearDown(state.dispose);
    await tester.pumpWidget(EasytierApp(state: state));
    await pumpFrames(tester);
    await openDestination(tester, EtDestination.config);

    expect(find.text('No network configured'), findsOneWidget);
    expect(find.text('Create network'), findsOneWidget);
    expect(find.byType(EtSection), findsNothing);
  });

  testWidgets('deleting the active network in Config confirms first, then removes it', (
    tester,
  ) async {
    final state = await pumpPhoneApp(tester);
    await openDestination(tester, EtDestination.config);

    expect(state.instances, hasLength(1));

    Future<void> openDelete() async {
      await tester.tap(find.byKey(const Key('config-overflow')));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Delete network').last);
      await pumpFrames(tester, frames: 12);
    }

    await openDelete();
    expect(find.text('Delete this network?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await pumpFrames(tester);
    expect(find.text('Delete this network?'), findsNothing);
    expect(state.instances, hasLength(1));

    await openDelete();
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpFrames(tester, frames: 12);

    expect(state.instances, isEmpty);
    expect(find.text('No network configured'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await pumpFrames(tester);
  });
}

/// A core with no configured instance, used to cover the empty state.
class _EmptyCoreClient implements CoreClient {
  @override
  Future<void> init() async {}

  @override
  Future<List<NetworkInstance>> listInstances() async => const [];

  @override
  Future<String> runInstance(NetworkConfig config) async => 'none';

  @override
  Future<void> stopInstance(String id) async {}

  @override
  Future<void> deleteInstance(String id) async {}

  @override
  Future<void> saveConfig(NetworkConfig config) async {}

  @override
  Future<NetworkConfig?> getConfig(String id) async => null;

  @override
  Future<String?> validateConfig(NetworkConfig config) async => null;

  @override
  Future<InstanceStatus> collectStatus(String id) async => InstanceStatus.stopped;

  @override
  Future<String> version() async => 'test-core';

  @override
  Stream<NetworkEvent> get events => const Stream<NetworkEvent>.empty();

  @override
  Future<void> dispose() async {}
}
