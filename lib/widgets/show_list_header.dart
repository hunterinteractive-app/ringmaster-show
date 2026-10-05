import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Gives the home title full width on phones, with actions on a second row.
class ShowListHeader extends StatelessWidget {
  const ShowListHeader({
    super.key,
    required this.height,
    required this.actions,
    this.demoMode = false,
  });

  final double height;
  final List<Widget> actions;
  final bool demoMode;

  static String subtitle(bool demoMode) =>
      demoMode ? 'Demo Mode — RingMaster Show' : 'Upcoming Shows';

  static bool compact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600 ||
      MediaQuery.textScalerOf(context).scale(20) > 26;

  static double heightFor(BuildContext context, {bool demoMode = false}) {
    if (!compact(context)) return 92;
    final width = MediaQuery.sizeOf(context).width - 32;
    double measure(String text, double size, FontWeight weight) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            fontWeight: weight,
            fontFamily: Theme.of(context).textTheme.titleLarge?.fontFamily,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: width);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return measure('RingMaster Show', 24, FontWeight.w800) +
        measure(subtitle(demoMode), 15, FontWeight.w500) +
        2 +
        24 +
        56;
  }

  @override
  Widget build(BuildContext context) {
    final narrow = compact(context);
    final title = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RingMaster Show',
          softWrap: true,
          maxLines: 5,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: AppColors.headerText,
            fontSize: narrow ? 24 : 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle(demoMode),
          softWrap: true,
          maxLines: 5,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: AppColors.headerText.withValues(alpha: .82),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: height,
      titleSpacing: 16,
      title: narrow
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                SizedBox(height: 56, child: Row(children: actions)),
              ],
            )
          : Row(
              children: [
                Image.asset(
                  'assets/images/RingMaster_One_Show_Transparent.png',
                  excludeFromSemantics: true,
                  height: 80,
                  width: 128,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 8),
                Expanded(child: title),
              ],
            ),
      actions: narrow ? null : [...actions, const SizedBox(width: 10)],
    );
  }
}
