import 'package:flutter/material.dart';

import '../../../data/models/report_models.dart';

class ReportTabMeta {
  const ReportTabMeta({
    required this.type,
    required this.title,
    required this.icon,
    required this.color,
    required this.bg,
  });

  final ReportType type;
  final String title;
  final IconData icon;
  final Color color;
  final Color bg;
}

const List<ReportTabMeta> kReportTabs = <ReportTabMeta>[
  ReportTabMeta(
    type: ReportType.trip,
    title: 'Trips',
    icon: Icons.alt_route_rounded,
    color: Color(0xFF9333EA),
    bg: Color(0xFFF3E8FF),
  ),
  ReportTabMeta(
    type: ReportType.dailyTrip,
    title: 'Full Day Trips',
    icon: Icons.route_rounded,
    color: Color(0xFF10B981),
    bg: Color(0xFFD1FAE5),
  ),
  ReportTabMeta(
    type: ReportType.ignition,
    title: 'Engine On / Off',
    icon: Icons.power_settings_new_rounded,
    color: Color(0xFFF59E0B),
    bg: Color(0xFFFEF3C7),
  ),
  ReportTabMeta(
    type: ReportType.distance,
    title: 'Day Wise Distance Report',
    icon: Icons.trending_up_rounded,
    color: Color(0xFF0284C7),
    bg: Color(0xFFE0F2FE),
  ),
  ReportTabMeta(
    type: ReportType.overspeeding,
    title: 'Overspeeding',
    icon: Icons.speed_rounded,
    color: Color(0xFFE11D48),
    bg: Color(0xFFFFF1F2),
  ),
  ReportTabMeta(
    type: ReportType.stoppages,
    title: 'Stoppage',
    icon: Icons.pause_circle_rounded,
    color: Color(0xFFEA580C),
    bg: Color(0xFFFFF7ED),
  ),
  ReportTabMeta(
    type: ReportType.idle,
    title: 'Idle',
    icon: Icons.access_time_rounded,
    color: Color(0xFFD97706),
    bg: Color(0xFFFEF3C7),
  ),
  ReportTabMeta(
    type: ReportType.consolidated,
    title: 'Consolidated',
    icon: Icons.group_work_rounded,
    color: Color(0xFF16A34A),
    bg: Color(0xFFF0FDF4),
  ),
  ReportTabMeta(
    type: ReportType.fuelConsolidated,
    title: 'Fuel Consolidated',
    icon: Icons.local_gas_station_rounded,
    color: Color(0xFFEA580C),
    bg: Color(0xFFFFF7ED),
  ),
  ReportTabMeta(
    type: ReportType.individual,
    title: 'Individual',
    icon: Icons.person_rounded,
    color: Color(0xFF2563EB),
    bg: Color(0xFFEFF6FF),
  ),
];

class ReportTopTabs extends StatelessWidget {
  const ReportTopTabs({
    required this.selectedType,
    required this.onTabSelected,
    super.key,
  });

  final ReportType selectedType;
  final ValueChanged<ReportType> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: kReportTabs.map((ReportTabMeta tab) {
            final bool isActive = tab.type == selectedType ||
                (tab.type == ReportType.trip &&
                    selectedType == ReportType.manualTrip);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onTabSelected(tab.type),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? tab.bg : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isActive ? tab.color : const Color(0xFFE2E8F0),
                        width: isActive ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          tab.icon,
                          size: 16,
                          color: isActive ? tab.color : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tab.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                            color: isActive ? tab.color : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
