import 'package:flutter/material.dart';
import 'map_mode.dart';

/// 地図モードを切り替えるタブUI
class ModeSwitcher extends StatelessWidget {
  final MapMode currentMode;
  final void Function(MapMode) onModeChanged;

  const ModeSwitcher({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Tab(
              label: '散歩',
              icon: Icons.directions_walk,
              isSelected: currentMode == MapMode.normal,
              onTap: () => onModeChanged(MapMode.normal),
            ),
            _Tab(
              label: '再生',
              icon: Icons.play_circle_outline,
              isSelected: currentMode == MapMode.animation,
              onTap: () => onModeChanged(MapMode.animation),
              activeColor: const Color(0xFF2E7D32),
            ),
            _Tab(
              label: '霧',
              icon: Icons.cloud_outlined,
              isSelected: currentMode == MapMode.fog,
              onTap: () => onModeChanged(MapMode.fog),
              activeColor: Colors.indigo,
            ),
            _Tab(
              label: '対戦',
              icon: Icons.sports_kabaddi,
              isSelected: currentMode == MapMode.versus,
              onTap: () => onModeChanged(MapMode.versus),
              activeColor: const Color(0xFFD32F2F),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Color activeColor;

  const _Tab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.activeColor = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.black54,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
