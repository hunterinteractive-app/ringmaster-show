// lib/widgets/rm_timezone_notice_banner.dart

import 'package:flutter/material.dart';

class RMTimezoneNoticeBanner extends StatefulWidget {
  final Duration duration;

  const RMTimezoneNoticeBanner({
    super.key,
    this.duration = const Duration(minutes: 5),
  });

  @override
  State<RMTimezoneNoticeBanner> createState() => _RMTimezoneNoticeBannerState();
}

class _RMTimezoneNoticeBannerState extends State<RMTimezoneNoticeBanner> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (!mounted) return;
      setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: !_visible
          ? const SizedBox.shrink()
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFB8D0FF)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(
                    Icons.access_time,
                    size: 18,
                    color: Color(0xFF11285A),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'All time is adjusted for your current time zone.',
                      style: TextStyle(
                        color: Color(0xFF11285A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}