import 'package:flutter/material.dart';

import '../../../models/dashboard_models.dart';
import '../../../theme/app_theme.dart';
import '../ino_card.dart';
import '../section_header.dart';
import '../../pressable_scale.dart';

/// Section 11 — Family & Events Center.
///
/// High-visibility horizontal row of upcoming birthdays, anniversaries and
/// family events. Each card leads with a warm gradient icon, the relative
/// countdown ("in 5 days") and the date — the emotional heart of the app.
class FamilySection extends StatelessWidget {
  const FamilySection({super.key, required this.events});

  final List<FamilyEvent> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Family & Events',
          subtitle: 'Never miss a moment',
          actionLabel: 'All events',
          icon: Icons.celebration_rounded,
        ),
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            physics: const BouncingScrollPhysics(),
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _EventCard(event: events[i]),
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final FamilyEvent event;

  List<Color> _gradient() {
    switch (event.type) {
      case FamilyEventType.birthday:
        return const [Color(0xFFEC6A8C), Color(0xFFF59BB3)];
      case FamilyEventType.anniversary:
        return const [Color(0xFF8B6CEF), Color(0xFFB59BF5)];
      case FamilyEventType.event:
        return const [AppColors.primaryGreen, AppColors.lightBlue];
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final g = _gradient();
    return PressableScale(
      child: SizedBox(
        width: 200,
        child: InoCard(
          padding: const EdgeInsets.all(14),
          onTap: () {},
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: g),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: g.first.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(event.icon, color: Colors.white, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      event.relativeDay,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: g.first,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 11, color: palette.textFaint),
                        const SizedBox(width: 4),
                        Text(
                          event.date,
                          style: TextStyle(
                              fontSize: 11.5, color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
