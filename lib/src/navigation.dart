import 'package:flutter/material.dart';

import 'models.dart';
import 'ui_components.dart';

class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.currentTab,
    required this.onSelected,
  });

  final BodyWornTab currentTab;
  final ValueChanged<BodyWornTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = currentTab == BodyWornTab.record || currentTab == BodyWornTab.ptt;
    final background = dark ? const Color(0xFF11141B) : Colors.white;
    final borderColor = dark ? const Color(0xFF1D2330) : const Color(0xFFDDE3EE);
    final selectedColor = currentTab == BodyWornTab.ptt
        ? const Color(0xFFFF6A6A)
        : dark
            ? Colors.white
            : kBluePrimary;
    final unselectedColor = dark ? const Color(0xFF7D8797) : const Color(0xFF9EA8B6);

    final items = [
      (BodyWornTab.home, Icons.grid_view_rounded, 'Beranda'),
      (BodyWornTab.record, Icons.videocam_rounded, 'Rekam'),
      (BodyWornTab.map, Icons.place_outlined, 'Peta'),
      (BodyWornTab.ptt, Icons.mic_none_rounded, 'PTT/HT'),
      (BodyWornTab.gallery, Icons.video_library_outlined, 'Rekaman'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: borderColor, width: 0.8)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelected(item.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: currentTab == item.$1
                              ? selectedColor.withValues(alpha: dark ? 0.14 : 0.10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          item.$2,
                          size: 22,
                          color: currentTab == item.$1
                              ? selectedColor
                              : unselectedColor,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.$3,
                        style: TextStyle(
                          color: currentTab == item.$1
                              ? selectedColor
                              : unselectedColor,
                          fontSize: 11,
                          fontWeight: currentTab == item.$1
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MockMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFD6DEE9)
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final dy = size.height / 4 * i;
      final dx = size.width / 4 * i;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), grid);
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), grid);
    }

    final route = Paint()
      ..color = const Color(0xFF6E95D5)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.1, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.45,
        size.width * 0.58,
        size.height * 0.53,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.63,
        size.width * 0.9,
        size.height * 0.15,
      );
    canvas.drawPath(path, route);

    final current = Offset(size.width * 0.5, size.height * 0.37);
    canvas.drawCircle(
      current,
      19,
      Paint()..color = const Color(0xFF2F66B4).withValues(alpha: 0.12),
    );
    canvas.drawCircle(current, 10, Paint()..color = const Color(0xFF2F66B4));
    canvas.drawCircle(
      Offset(size.width * 0.3, size.height * 0.48),
      4,
      Paint()..color = const Color(0xFFE57373),
    );
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.25),
      4,
      Paint()..color = const Color(0xFF48B687),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
