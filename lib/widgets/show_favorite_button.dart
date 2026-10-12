import 'dart:math' as math;
import 'package:flutter/material.dart';

class ShowFavoriteButton extends StatelessWidget {
  const ShowFavoriteButton({
    super.key,
    required this.selected,
    required this.onPressed,
  });
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: CustomPaint(
      size: const Size(24, 24),
      painter: _StarPainter(
        selected,
        selected
            ? const Color(0xFF966300)
            : Theme.of(context).colorScheme.primary,
      ),
    ),
    label: Text(selected ? 'Favorited' : 'Favorite'),
  );
}

// Draw directly so a previously cached subset of the icon font cannot hide it.
class _StarPainter extends CustomPainter {
  const _StarPainter(this.selected, this.color);
  final bool selected;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 1;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? radius : radius * .45;
      final point = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = selected ? PaintingStyle.fill : PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_StarPainter oldDelegate) =>
      selected != oldDelegate.selected || color != oldDelegate.color;
}
