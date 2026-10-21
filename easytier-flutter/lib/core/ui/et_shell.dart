import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/theme.dart';

enum EtDestination { home, devices, config, activity, settings }

extension EtDestinationInfo on EtDestination {
  String get label => switch (this) {
    EtDestination.home => 'Home',
    EtDestination.devices => 'Devices',
    EtDestination.config => 'Config',
    EtDestination.activity => 'Activity',
    EtDestination.settings => 'Settings',
  };

  IconData get icon => switch (this) {
    EtDestination.home => Symbols.shield,
    EtDestination.devices => Symbols.devices,
    EtDestination.config => Symbols.tune,
    EtDestination.activity => Symbols.monitoring,
    EtDestination.settings => Symbols.settings,
  };

  IconData get selectedIcon => icon;
}

/// Navigation frame: M3 `NavigationBar` on phones, `NavigationRail` on desktop.
class EtShell extends StatelessWidget {
  const EtShell({
    super.key,
    required this.current,
    required this.onSelect,
    required this.child,
    this.activityBadge = 0,
  });

  final EtDestination current;
  final ValueChanged<EtDestination> onSelect;
  final Widget child;
  final int activityBadge;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    final desktop = context.etUseRail;

    if (!desktop) {
      return Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(bottom: false, child: child),
        bottomNavigationBar: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: current.index,
            onDestinationSelected: (index) => onSelect(EtDestination.values[index]),
            destinations: [
              for (final destination in EtDestination.values)
                NavigationDestination(
                  icon: _withBadge(
                    Icon(destination.icon),
                    destination == EtDestination.activity ? activityBadge : 0,
                  ),
                  selectedIcon: _withBadge(
                    Icon(destination.selectedIcon),
                    destination == EtDestination.activity ? activityBadge : 0,
                  ),
                  label: destination.label,
                  tooltip: destination.label,
                ),
            ],
          ),
        ),
      );
    }

    final extended = MediaQuery.sizeOf(context).width >= 1200;
    return Scaffold(
      backgroundColor: p.bg,
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: current.index,
            extended: extended,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            groupAlignment: -0.9,
            onDestinationSelected: (index) => onSelect(EtDestination.values[index]),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: EtSpace.x6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: p.scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Symbols.shield,
                      color: p.scheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  if (extended) ...[
                    const SizedBox(width: EtSpace.x3),
                    Text(
                      'EasyTier',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            destinations: [
              for (final destination in EtDestination.values)
                NavigationRailDestination(
                  icon: _withBadge(
                    Icon(destination.icon),
                    destination == EtDestination.activity ? activityBadge : 0,
                  ),
                  selectedIcon: _withBadge(
                    Icon(destination.selectedIcon),
                    destination == EtDestination.activity ? activityBadge : 0,
                  ),
                  label: Text(destination.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: EtSpace.maxContentWidth + 96),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _withBadge(Widget icon, int count) {
    if (count <= 0) return icon;
    return Badge.count(count: count > 99 ? 99 : count, child: icon);
  }
}

/// Standard page frame: an M3 small top app bar plus a body.
class EtPage extends StatelessWidget {
  const EtPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(EtSpace.x4, EtSpace.x2, EtSpace.x4, EtSpace.x6),
    this.showHeader = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsets padding;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: showHeader
          ? AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (subtitle != null)
                    AnimatedSwitcher(
                      duration: EtDuration.fast,
                      switchInCurve: EtCurves.enter,
                      switchOutCurve: EtCurves.exit,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: AlignmentDirectional.centerStart,
                        children: [...previous, ?current],
                      ),
                      child: Text(
                        subtitle!,
                        key: ValueKey<String>(subtitle!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EtText.ui(size: EtType.caption, color: p.text2),
                      ),
                    ),
                ],
              ),
              toolbarHeight: kToolbarHeight,
              actions: [
                for (final action in actions)
                  Padding(
                    padding: const EdgeInsets.only(right: EtSpace.x1),
                    child: action,
                  ),
                const SizedBox(width: EtSpace.x2),
              ],
            )
          : null,
      body: Padding(padding: padding, child: child),
    );
  }
}

/// Vertically scrolling body with a readable max width and the page gutter.
class EtScrollBody extends StatelessWidget {
  const EtScrollBody({super.key, required this.children, this.top = 0, this.bottom = EtSpace.x6});

  final List<Widget> children;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.only(top: top, bottom: bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: EtSpace.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: EtSpace.x4),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings-style navigation row: M3 `ListTile`.
class EtTile extends StatelessWidget {
  const EtTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.et;
    return ListTile(
      onTap: onTap,
      leading: icon == null ? null : Icon(icon, color: destructive ? p.danger : p.text2),
      title: Text(
        title,
        style: EtText.ui(
          size: EtType.bodySm,
          weight: FontWeight.w500,
          color: destructive ? p.danger : p.text,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ??
          (onTap == null ? null : Icon(Symbols.chevron_right, color: p.text2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: EtSpace.x2),
    );
  }
}

/// Standard icon button with tooltip (48dp target from Material).
class EtIconButton extends StatelessWidget {
  const EtIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: color),
    );
  }
}
