// lib/widgets/ringmaster_page_shell.dart

import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/services/app_session.dart';
import 'package:ringmaster_show/screens/show_list_screen.dart';
import 'package:ringmaster_show/widgets/help_report_dialog.dart';

class RingMasterPageShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;

  final bool showHomeButton;
  final bool showBackButton;
  final VoidCallback? onBack;

  final List<Widget>? actions;
  final Widget? leading;
  final Widget? logo;

  final bool useScrollView;
  final EdgeInsetsGeometry bodyPadding;
  final Color? backgroundColor;
  final Color? headerColor;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  final String? showId;
  final bool showHelpButton;

  const RingMasterPageShell({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.showHomeButton = true,
    this.showBackButton = true,
    this.onBack,
    this.actions,
    this.leading,
    this.logo,
    this.useScrollView = false,
    this.bodyPadding = const EdgeInsets.all(16),
    this.backgroundColor,
    this.headerColor,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.showId,
    this.showHelpButton = true,
  });

  bool _canPop(BuildContext context) {
    return Navigator.of(context).canPop();
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final routeName = route?.settings.name;
    final routeArgs = route?.settings.arguments;
    final effectiveShowId = showId ?? _showIdFromRouteArguments(routeArgs);
    final isSupportMode = AppSession.isSupportMode;
    final impersonatedLabel =
        AppSession.impersonatedUserName ??
        AppSession.impersonatedUserEmail ??
        AppSession.impersonatedUserId ??
        AppSession.effectiveUserId;
    final screenWidth = MediaQuery.of(context).size.width;

    final isMobile = screenWidth < 700;
    final isTablet = screenWidth >= 700 && screenWidth < 1100;

    final theme = Theme.of(context);
    final topColor = headerColor ?? theme.colorScheme.primary;
    final headerForeground = _foregroundFor(topColor);
    final pageBg = backgroundColor ?? theme.scaffoldBackgroundColor;

    final horizontalPadding = isMobile
        ? 16.0
        : isTablet
        ? 20.0
        : 24.0;

    final topPadding = isMobile ? 12.0 : 16.0;
    final bottomRadius = isMobile ? 24.0 : 28.0;
    final pageDecoration = BoxDecoration(
      color: backgroundColor,
      gradient: backgroundColor == null ? AppGradients.page : null,
      borderRadius: BorderRadius.vertical(top: Radius.circular(bottomRadius)),
    );

    final logoSize = isMobile
        ? 48.0
        : isTablet
        ? 58.0
        : 64.0;

    // Mobile header size
    final titleSize = isMobile
        ? 24.0
        : isTablet
        ? 34.0
        : 38.0;

    final subtitleSize = isMobile
        ? 15.0
        : isTablet
        ? 17.0
        : 18.0;

    final iconSize = isMobile ? 22.0 : 24.0;

    final shouldShowBack =
        leading != null || (showBackButton && _canPop(context));

    Widget resolvedBody = useScrollView
        ? SingleChildScrollView(padding: bodyPadding, child: body)
        : Padding(padding: bodyPadding, child: body);

    final resolvedActions = <Widget>[
      ...(actions ?? const []),
      if (showHomeButton)
        IconButton(
          tooltip: 'Home',
          icon: const Icon(Icons.home_outlined),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ShowListScreen()),
              (route) => false,
            );
          },
        ),
      if (showHelpButton)
        IconButton(
          tooltip: 'Report an issue',
          icon: const Icon(Icons.help_outline),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => HelpReportDialog(
              pageTitle: title,
              pageRoute: routeName,
              showId: effectiveShowId,
            ),
          ),
        ),
    ];

    return Scaffold(
      backgroundColor: topColor,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (isSupportMode)
              _SupportModeBanner(
                label: impersonatedLabel,
                onExit: () {
                  AppSession.stopImpersonation();

                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const ShowListScreen()),
                    (route) => false,
                  );
                },
              ),
            Container(
              color: topColor,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                topPadding,
                horizontalPadding,
                18,
              ),
              child: isMobile
                  ? _MobileHeader(
                      title: title,
                      subtitle: subtitle,
                      logo: logo,
                      leading: leading,
                      showBack: shouldShowBack,
                      onBack: onBack,
                      actions: resolvedActions,
                      topColor: topColor,
                      foregroundColor: headerForeground,
                      logoSize: logoSize,
                      titleSize: titleSize,
                      subtitleSize: subtitleSize,
                      iconSize: iconSize,
                    )
                  : _WideHeader(
                      title: title,
                      subtitle: subtitle,
                      logo: logo,
                      leading: leading,
                      showBack: shouldShowBack,
                      onBack: onBack,
                      actions: resolvedActions,
                      topColor: topColor,
                      foregroundColor: headerForeground,
                      logoSize: logoSize,
                      titleSize: titleSize,
                      subtitleSize: subtitleSize,
                      iconSize: iconSize,
                    ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: pageDecoration,
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(bottomRadius),
                  ),
                  child: Material(
                    color: backgroundColor == null
                        ? Colors.transparent
                        : pageBg,
                    child: resolvedBody,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportModeBanner extends StatelessWidget {
  final String? label;
  final VoidCallback onExit;

  const _SupportModeBanner({required this.label, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final displayLabel = label == null || label!.trim().isEmpty
        ? 'another user'
        : label!.trim();

    return Container(
      width: double.infinity,
      color: AppColors.warningBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            const Icon(
              Icons.visibility_outlined,
              size: 18,
              color: AppColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Viewing as $displayLabel — support mode',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onExit,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Exit'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.warning,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _showIdFromRouteArguments(Object? args) {
  if (args == null) return null;

  if (args is String && args.trim().isNotEmpty) {
    return args.trim();
  }

  if (args is Map) {
    final possibleKeys = ['showId', 'show_id', 'id'];

    for (final key in possibleKeys) {
      final value = args[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
  }

  return null;
}

class _MobileHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? logo;
  final Widget? leading;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Color topColor;
  final Color foregroundColor;
  final double logoSize;
  final double titleSize;
  final double subtitleSize;
  final double iconSize;

  const _MobileHeader({
    required this.title,
    required this.subtitle,
    required this.logo,
    required this.leading,
    required this.showBack,
    required this.onBack,
    required this.actions,
    required this.topColor,
    required this.foregroundColor,
    required this.logoSize,
    required this.titleSize,
    required this.subtitleSize,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final canShowLogo = logo != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showBack)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child:
                    leading ??
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.arrow_back,
                        color: foregroundColor,
                        size: iconSize,
                      ),
                      onPressed:
                          onBack ?? () => Navigator.of(context).maybePop(),
                    ),
              ),
            if (canShowLogo)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: logoSize,
                  height: logoSize,
                  child: FittedBox(fit: BoxFit.contain, child: logo),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foregroundColor,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foregroundColor.withValues(alpha: .82),
                          fontSize: subtitleSize,
                          fontWeight: FontWeight.w400,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _LimitedHeaderActions(
            actions: actions,
            foregroundColor: foregroundColor,
            spacing: 6,
          ),
        ],
      ],
    );
  }
}

class _WideHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? logo;
  final Widget? leading;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Color topColor;
  final Color foregroundColor;
  final double logoSize;
  final double titleSize;
  final double subtitleSize;
  final double iconSize;

  const _WideHeader({
    required this.title,
    required this.subtitle,
    required this.logo,
    required this.leading,
    required this.showBack,
    required this.onBack,
    required this.actions,
    required this.topColor,
    required this.foregroundColor,
    required this.logoSize,
    required this.titleSize,
    required this.subtitleSize,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child:
                leading ??
                IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: foregroundColor,
                    size: iconSize,
                  ),
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                ),
          ),
        if (logo != null)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: logoSize,
              height: logoSize,
              child: FittedBox(fit: BoxFit.contain, child: logo),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor.withValues(alpha: .82),
                    fontSize: subtitleSize,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty)
          _LimitedHeaderActions(
            actions: actions,
            foregroundColor: foregroundColor,
            spacing: 8,
          ),
      ],
    );
  }
}

class _LimitedHeaderActions extends StatelessWidget {
  static const int maxVisibleIcons = 3;

  final List<Widget> actions;
  final Color foregroundColor;
  final double spacing;

  const _LimitedHeaderActions({
    required this.actions,
    required this.foregroundColor,
    required this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    final hasOverflow = actions.length > maxVisibleIcons;
    final directCount = hasOverflow ? maxVisibleIcons - 1 : actions.length;
    final directActions = actions.take(directCount);
    final overflowActions = hasOverflow
        ? actions.skip(directCount).toList()
        : const <Widget>[];

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final action in directActions)
          _HeaderActionContainer(
            foregroundColor: foregroundColor,
            child: action,
          ),
        if (overflowActions.isNotEmpty)
          _HeaderOverflowMenu(
            actions: overflowActions,
            foregroundColor: foregroundColor,
          ),
      ],
    );
  }
}

class _HeaderOverflowMenu extends StatelessWidget {
  final List<Widget> actions;
  final Color foregroundColor;

  const _HeaderOverflowMenu({
    required this.actions,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final menuActions = actions.map(_HeaderMenuAction.fromWidget).toList();

    return PopupMenuButton<int>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert, color: foregroundColor),
      onSelected: (index) => menuActions[index].onPressed?.call(),
      itemBuilder: (context) => [
        for (var index = 0; index < menuActions.length; index++)
          PopupMenuItem<int>(
            value: index,
            enabled: menuActions[index].onPressed != null,
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(color: AppColors.text, size: 20),
                  child: menuActions[index].icon,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(menuActions[index].label)),
              ],
            ),
          ),
      ],
    );
  }
}

class _HeaderMenuAction {
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  const _HeaderMenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  factory _HeaderMenuAction.fromWidget(Widget action) {
    if (action is IconButton) {
      return _HeaderMenuAction(
        icon: action.icon,
        label: action.tooltip ?? 'Action',
        onPressed: action.onPressed,
      );
    }

    if (action is Tooltip) {
      return _HeaderMenuAction(
        icon: const Icon(Icons.circle_outlined),
        label: action.message ?? 'Action',
        onPressed: null,
      );
    }

    return const _HeaderMenuAction(
      icon: Icon(Icons.circle_outlined),
      label: 'Action',
      onPressed: null,
    );
  }
}

class _HeaderActionContainer extends StatelessWidget {
  final Widget child;
  final Color foregroundColor;

  const _HeaderActionContainer({
    required this.foregroundColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return IconTheme(
      data: IconThemeData(color: foregroundColor),
      child: DefaultTextStyle(
        style: TextStyle(color: foregroundColor),
        child: child,
      ),
    );
  }
}

Color _foregroundFor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? AppColors.headerForeground
      : AppColors.text;
}
