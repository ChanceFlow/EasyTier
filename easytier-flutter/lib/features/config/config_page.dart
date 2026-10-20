import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/theme.dart';
import '../../core/ui/ui.dart';
import 'acl_config_section.dart';
import 'acl_rule_sheet.dart';
import 'advanced_config_section.dart';
import 'basic_config_section.dart';
import 'config_form.dart';
import 'config_validation.dart';
import 'config_widgets.dart';
import 'port_forward_config_section.dart';
import 'port_forward_sheet.dart';
import 'toml_preview_sheet.dart';

/// Config: the expert form. Four one-level disclosure sections, every field of
/// [NetworkConfig] surfaced, no presets, no nested expansion.
///
/// The screen edits a local draft ([ConfigForm]); the saved configuration is
/// only replaced by an explicit Save / Run. Field errors name the offending
/// segment, and a failed submit also raises a focusable summary at the top.
class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  ConfigForm? _form;
  String? _boundInstanceId;
  NetworkConfig? _boundConfig;
  NetworkConfig? _baseline;

  Map<String, String> _errors = const {};
  final List<String> _coreErrors = [];
  String? _saveError;
  final List<int> _sectionEpoch = [0, 0, 0, 0];
  int _errorEpoch = 0;

  bool _revealSecret = false;
  bool _saving = false;
  bool _running = false;
  bool _dirty = false;

  final FocusNode _summaryFocus = FocusNode();

  @override
  void dispose() {
    _form?.dispose();
    _summaryFocus.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Draft <-> saved config synchronisation.
  // -------------------------------------------------------------------------

  void _syncDraft(NetworkInstance active, String activeId) {
    final form = _form;
    final wasDirty =
        form != null &&
        _baseline != null &&
        !configEquals(form.config, _baseline!);
    final instanceChanged = _boundInstanceId != activeId;
    final configChanged = form == null || !identical(active.config, _boundConfig);

    if (form == null || instanceChanged || (configChanged && !wasDirty)) {
      _retireForm(form);
      _form = ConfigForm(active.config);
      _boundInstanceId = activeId;
      _boundConfig = active.config;
      _baseline = active.config;
      _errors = const {};
      _coreErrors.clear();
      _saveError = null;
      _revealSecret = false;
    } else if (configChanged) {
      // The saved config changed underneath a dirty draft. Keep the user's
      // edits and remember the new identity so we do not resync every frame.
      _boundConfig = active.config;
    }
  }

  /// Controllers can still be referenced by the previous frame's text fields,
  /// so a retired draft is disposed after the frame that detached it.
  void _retireForm(ConfigForm? form) {
    if (form == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => form.dispose());
  }

  void _disposeDraft() {
    _retireForm(_form);
    _form = null;
    _boundInstanceId = null;
    _boundConfig = null;
    _baseline = null;
    _errors = const {};
    _coreErrors.clear();
    _saveError = null;
  }

  // -------------------------------------------------------------------------
  // Editing.
  // -------------------------------------------------------------------------

  void _onTextChanged(String field) {
    final form = _form;
    if (form == null) return;
    setState(() {
      if (_errors.containsKey(field)) {
        final message = form.validate()[field];
        if (message == null) {
          _errors = Map<String, String>.of(_errors)..remove(field);
        } else {
          _errors = Map<String, String>.of(_errors)..[field] = message;
        }
      }
      _coreErrors.clear();
      _saveError = null;
    });
  }

  void _onValuesChanged(NetworkConfig next) {
    final form = _form;
    if (form == null) return;
    setState(() {
      form.updateValues(next);
      if (next.dhcp) {
        _errors = Map<String, String>.of(_errors)
          ..remove(ConfigField.virtualIpv4)
          ..remove(ConfigField.networkLength);
      }
      _coreErrors.clear();
      _saveError = null;
    });
  }

  void _resetDraft() {
    final active = AppScope.read(context).active;
    final form = _form;
    if (active == null || form == null) return;
    setState(() {
      form.reseed(active.config);
      _baseline = active.config;
      _boundConfig = active.config;
      _errors = const {};
      _coreErrors.clear();
      _saveError = null;
      _revealSecret = false;
    });
  }

  // -------------------------------------------------------------------------
  // Saving / running.
  // -------------------------------------------------------------------------

  Future<bool> _saveDraft({bool announce = true}) async {
    final state = AppScope.read(context);
    final form = _form;
    if (form == null) return false;

    final errors = form.validate();
    if (errors.isNotEmpty) {
      _showValidationErrors(errors);
      return false;
    }

    final draft = form.config;
    final coreError = await state.validateConfig(draft);
    if (!mounted) return false;
    if (coreError != null) {
      _showCoreError(coreError);
      return false;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });
    final saved = await state.saveConfig(draft);
    if (!mounted) return false;
    final boundConfig = state.active?.config;
    final boundId = state.activeId;
    setState(() {
      _saving = false;
      if (saved) {
        _baseline = draft;
        _boundConfig = boundConfig ?? draft;
        _boundInstanceId = boundId ?? _boundInstanceId;
        _errors = const {};
        _coreErrors.clear();
        _saveError = null;
      } else {
        _saveError = state.lastError ?? 'The core rejected the configuration.';
      }
    });
    if (saved && announce) _showSnack('Configuration saved.');
    return saved;
  }

  Future<void> _runWithSettings() async {
    final state = AppScope.read(context);
    if (_running) return;
    setState(() => _running = true);
    try {
      final saved = await _saveDraft(announce: false);
      if (!saved) return;
      if (!mounted) return;
      if (state.status.phase.isUp) {
        await state.disconnect();
        if (!mounted) return;
      }
      await state.connect();
      if (!mounted) return;
      final error = state.lastError;
      if (error != null) {
        _showSnack('Could not start the network: $error');
      } else {
        _showSnack(
          state.status.phase.isUp
              ? 'Network started with the saved settings.'
              : 'Network is starting…',
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _showValidationErrors(Map<String, String> errors) {
    setState(() {
      _errors = Map<String, String>.of(errors);
      _coreErrors.clear();
      _saveError = null;
      _errorEpoch++;
      for (final field in errors.keys) {
        final section = kConfigFieldSection[field];
        if (section != null) _sectionEpoch[section] = _sectionEpoch[section] + 1;
      }
    });
    _focusSummary();
  }

  void _showCoreError(String message) {
    final field = fieldForCoreError(message);
    setState(() {
      _coreErrors.clear();
      if (field == null) {
        _coreErrors.add(message);
      } else {
        _errors = Map<String, String>.of(_errors)..[field] = message;
        final section = kConfigFieldSection[field];
        if (section != null) _sectionEpoch[section] = _sectionEpoch[section] + 1;
      }
      _errorEpoch++;
      _saveError = null;
    });
    _focusSummary();
  }

  void _focusSummary() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_summaryFocus.canRequestFocus) _summaryFocus.requestFocus();
    });
  }

  List<String> _summaryLines() {
    final lines = <String>[];
    for (final field in kConfigFieldOrder) {
      final message = _errors[field];
      if (message == null) continue;
      lines.add('${kConfigFieldLabels[field] ?? field}: $message');
    }
    for (final entry in _errors.entries) {
      if (kConfigFieldOrder.contains(entry.key)) continue;
      lines.add('${kConfigFieldLabels[entry.key] ?? entry.key}: ${entry.value}');
    }
    lines.addAll(_coreErrors);
    return lines;
  }

  String _summaryTitle(List<String> lines) {
    if (_errors.isEmpty) return 'The core rejected this configuration';
    return lines.length == 1 ? '1 field needs attention' : '${lines.length} fields need attention';
  }

  // -------------------------------------------------------------------------
  // Network switching / list editing.
  // -------------------------------------------------------------------------

  Future<void> _addNetwork() async {
    final state = AppScope.read(context);
    if (!await _confirmDiscard()) return;
    await state.addInstance();
  }

  Future<void> _selectInstance(String id) async {
    final state = AppScope.read(context);
    if (id == state.activeId) return;
    if (!await _confirmDiscard()) return;
    await state.selectInstance(id);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final p = context.et;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
          'This network has a draft that has not been saved yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: p.danger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _addPortForward() async {
    final form = _form;
    if (form == null) return;
    final rule = await showEtSheet<PortForward>(
      context: context,
      builder: (_) => PortForwardSheet(existing: form.values.portForwards),
    );
    if (rule == null || !mounted) return;
    final next = List<PortForward>.of(form.values.portForwards)..add(rule);
    _onValuesChanged(form.values.copyWith(portForwards: next));
  }

  void _deletePortForward(int index) {
    final form = _form;
    if (form == null || index >= form.values.portForwards.length) return;
    final next = List<PortForward>.of(form.values.portForwards)
      ..removeAt(index);
    _onValuesChanged(form.values.copyWith(portForwards: next));
  }

  Future<void> _addAclRule() async {
    final form = _form;
    if (form == null) return;
    final rule = await showEtSheet<AclRule>(
      context: context,
      builder: (_) => const AclRuleSheet(),
    );
    if (rule == null || !mounted) return;
    final next = List<AclRule>.of(form.values.aclRules)..add(rule);
    _onValuesChanged(form.values.copyWith(aclRules: next));
  }

  void _deleteAclRule(int index) {
    final form = _form;
    if (form == null || index >= form.values.aclRules.length) return;
    final next = List<AclRule>.of(form.values.aclRules)..removeAt(index);
    _onValuesChanged(form.values.copyWith(aclRules: next));
  }

  void _openTomlPreview(NetworkConfig draft) {
    showEtSheet<void>(
      context: context,
      builder: (_) => TomlPreviewSheet(config: draft),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // -------------------------------------------------------------------------
  // Build.
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final active = state.active;
    final activeId = state.activeId;
    if (active == null || activeId == null) {
      _disposeDraft();
      return _buildEmptyState(context, state);
    }

    _syncDraft(active, activeId);
    final form = _form!;
    final draft = form.config;
    final dirty = !configEquals(draft, _baseline ?? active.config);
    _dirty = dirty;

    final locked = _saving || _running || state.busy;
    final summaryLines = _summaryLines();
    final showSummary = summaryLines.isNotEmpty;

    final banners = <Widget>[
      if (_saveError != null)
        EtBanner(
          tone: EtTone.danger,
          icon: Symbols.error,
          title: 'Could not save',
          message: _saveError,
          actions: [
            IconButton(
              icon: const Icon(Symbols.close),
              tooltip: 'Dismiss',
              onPressed: () => setState(() => _saveError = null),
            ),
          ],
        ),
      if (showSummary)
        Semantics(
          container: true,
          liveRegion: true,
          label:
              '${_summaryTitle(summaryLines)}. ${_summaryMessage(summaryLines)}',
          child: Focus(
            focusNode: _summaryFocus,
            child: EtBanner(
              key: ValueKey('config-error-summary-$_errorEpoch'),
              tone: EtTone.danger,
              icon: Symbols.error,
              title: _summaryTitle(summaryLines),
              message: _summaryMessage(summaryLines),
            ),
          ),
        ),
      if (dirty)
        EtBanner(
          tone: EtTone.warn,
          icon: Symbols.edit,
          title: 'Unsaved changes',
          message: 'The draft differs from the saved configuration.',
          actions: [
            TextButton(
              onPressed: locked ? null : _resetDraft,
              child: const Text('Reset'),
            ),
          ],
        ),
    ];

    return EtPage(
      title: 'Config',
      subtitle: active.config.networkName,
      actions: [
        EtIconButton(
          icon: Symbols.code,
          tooltip: 'Preview TOML',
          onPressed: () => _openTomlPreview(draft),
        ),
        EtIconButton(
          icon: Symbols.add,
          tooltip: 'Add network',
          onPressed: locked ? null : () => _addNetwork(),
        ),
      ],
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (banners.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EtSpace.x4,
                EtSpace.x2,
                EtSpace.x4,
                EtSpace.x1,
              ),
              child: ConfigStack(gap: EtSpace.x2, children: banners),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: EtSpace.x4),
              child: EtScrollBody(
                top: EtSpace.x2,
                // The action bar is anchored below the scroll area; the bottom
                // gutter is taller than the bar so no field can ever be hidden
                // behind it (IME inset / short screens).
                bottom: EtSpace.x16 * 3,
                children: [
                  ConfigInstanceCards(
                    instances: state.instances,
                    activeId: activeId,
                    enabled: !locked,
                    onSelect: _selectInstance,
                  ),
                  EtSection(
                    key: ValueKey('config-section-basic-${_sectionEpoch[0]}'),
                    title: 'Basic',
                    subtitle: 'Identity, network and addresses',
                    initiallyExpanded: true,
                    leading: _sectionBadge(
                      ConfigSectionIndex.basic,
                      icon: Symbols.devices,
                      tone: EtTone.accent,
                    ),
                    children: [
                      _sectionBody(
                        BasicConfigSection(
                          form: form,
                          errors: _errors,
                          enabled: !locked,
                          revealSecret: _revealSecret,
                          onToggleRevealSecret: () =>
                              setState(() => _revealSecret = !_revealSecret),
                          onTextChanged: _onTextChanged,
                          onValuesChanged: _onValuesChanged,
                        ),
                      ),
                    ],
                  ),
                  EtSection(
                    key: ValueKey(
                      'config-section-advanced-${_sectionEpoch[1]}',
                    ),
                    title: 'Advanced',
                    subtitle: 'Datapath, routing, privacy',
                    initiallyExpanded: _sectionEpoch[1] > 0,
                    leading: _sectionBadge(
                      ConfigSectionIndex.advanced,
                      icon: Symbols.tune,
                      tone: EtTone.tertiary,
                    ),
                    children: [
                      _sectionBody(
                        AdvancedConfigSection(
                          form: form,
                          errors: _errors,
                          enabled: !locked,
                          onTextChanged: _onTextChanged,
                          onValuesChanged: _onValuesChanged,
                        ),
                      ),
                    ],
                  ),
                  EtSection(
                    key: ValueKey(
                      'config-section-port-forward-${_sectionEpoch[2]}',
                    ),
                    title: 'Port forward',
                    subtitle: 'Expose local services through a peer',
                    initiallyExpanded: _sectionEpoch[2] > 0,
                    leading: _sectionBadge(
                      ConfigSectionIndex.portForward,
                      icon: Symbols.alt_route,
                      tone: EtTone.info,
                    ),
                    children: [
                      _sectionBody(
                        PortForwardConfigSection(
                          form: form,
                          errors: _errors,
                          enabled: !locked,
                          onTextChanged: _onTextChanged,
                          onValuesChanged: _onValuesChanged,
                          onAdd: _addPortForward,
                          onDelete: _deletePortForward,
                        ),
                      ),
                    ],
                  ),
                  EtSection(
                    key: ValueKey('config-section-acl-${_sectionEpoch[3]}'),
                    title: 'ACL',
                    subtitle: 'Allow or deny traffic per chain',
                    initiallyExpanded: _sectionEpoch[3] > 0,
                    leading: _sectionBadge(
                      ConfigSectionIndex.acl,
                      icon: Symbols.shield,
                      tone: EtTone.success,
                    ),
                    children: [
                      _sectionBody(
                        AclConfigSection(
                          form: form,
                          errors: _errors,
                          enabled: !locked,
                          onValuesChanged: _onValuesChanged,
                          onAdd: _addAclRule,
                          onDelete: _deleteAclRule,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _BottomActionBar(
            dirty: dirty,
            connected: state.status.phase.isUp,
            running: _running,
            saving: _saving,
            locked: locked,
            onSave: () => _saveDraft(),
            onRun: _runWithSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppState state) {
    return EtPage(
      title: 'Config',
      subtitle: 'No network',
      actions: [
        EtIconButton(
          icon: Symbols.add,
          tooltip: 'Add network',
          onPressed: () => _addNetwork(),
        ),
      ],
      child: EtEmptyState(
        icon: Symbols.lan,
        title: 'No network configured',
        message:
            'Configuration belongs to a network. Create one to set its '
            'identity, transport and rules.',
        action: EtPrimaryButton(
          label: 'Create network',
          icon: Symbols.add,
          expanded: false,
          onPressed: () => _addNetwork(),
        ),
      ),
    );
  }

  /// Expressive section accent: a tinted squircle in the header row, with the
  /// field-error count riding on an M3 badge.
  Widget _sectionBadge(
    int section, {
    required IconData icon,
    required EtTone tone,
  }) {
    final count = _errors.keys
        .where((field) => kConfigFieldSection[field] == section)
        .length;
    final badge = EtIconBadge(icon: icon, tone: tone, size: 40);
    if (count == 0) return badge;
    return Tooltip(
      message: count == 1
          ? '1 field needs attention'
          : '$count fields need attention',
      child: Badge.count(count: count, child: badge),
    );
  }

  /// Comfortable form padding: the kit's ExpansionTile already insets by 16,
  /// this adds 4/4/8 so field content breathes at 20dp inside a 24dp card.
  Widget _sectionBody(Widget child) => Padding(
    padding: const EdgeInsets.fromLTRB(
      EtSpace.x1,
      EtSpace.x1,
      EtSpace.x1,
      EtSpace.x2,
    ),
    child: child,
  );

  String _summaryMessage(List<String> lines) {
    final shown = lines.take(4).toList();
    if (lines.length > shown.length) {
      shown.add('…and ${lines.length - shown.length} more');
    }
    return shown.join('\n');
  }
}

/// M3 expressive bottom action bar: one filled primary Save pill, one quiet
/// secondary Run action, and the honest save status. It is a sibling below the
/// scroll body, so it can never paint over a field.
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.dirty,
    required this.connected,
    required this.running,
    required this.saving,
    required this.locked,
    required this.onSave,
    required this.onRun,
  });

  final bool dirty;
  final bool connected;
  final bool running;
  final bool saving;
  final bool locked;
  final VoidCallback onSave;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = context.et;
    final wide = context.etDesktop;

    final busy = running || saving;
    final status = running
        ? 'Applying settings…'
        : saving
        ? 'Saving…'
        : dirty
        ? 'Draft not saved'
        : 'All changes saved';
    final icon = busy
        ? Symbols.progress_activity
        : dirty
        ? Symbols.edit
        : Symbols.check_circle;
    final iconColor = busy
        ? scheme.primary
        : dirty
        ? scheme.onSurfaceVariant
        : p.success;
    final helper = connected
        ? 'Save stores the draft. Run restarts the running tunnel with it.'
        : 'Save stores the draft. Run starts the network with it.';

    final statusRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: EtSpace.x2),
        Flexible(
          child: Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );

    final save = EtPrimaryButton(
      label: 'Save',
      loading: saving,
      onPressed: dirty && !locked ? onSave : null,
    );
    final run = TextButton(
      onPressed: locked ? null : onRun,
      child: const Text('Run with these settings'),
    );

    return Material(
      key: const Key('config-bottom-bar'),
      elevation: 3,
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            EtSpace.x4,
            EtSpace.x3,
            EtSpace.x4,
            EtSpace.x3,
          ),
          child: wide
              ? Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          statusRow,
                          const SizedBox(height: 2),
                          Text(
                            helper,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: EtSpace.x4),
                    run,
                    const SizedBox(width: EtSpace.x3),
                    SizedBox(width: 220, child: save),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusRow,
                    const SizedBox(height: 2),
                    Text(
                      helper,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: EtSpace.x3),
                    save,
                    const SizedBox(height: EtSpace.x1),
                    Center(child: run),
                  ],
                ),
        ),
      ),
    );
  }
}
