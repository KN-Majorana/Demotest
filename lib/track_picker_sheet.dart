import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'walk_track.dart';

/// 保存済みの散歩記録から1件を選ぶボトムシート
class TrackPickerSheet extends StatelessWidget {
  final List<WalkTrack> tracks;
  final String? selectedId;

  const TrackPickerSheet({
    super.key,
    required this.tracks,
    this.selectedId,
  });

  static Future<WalkTrack?> show(
    BuildContext context, {
    required List<WalkTrack> tracks,
    String? selectedId,
  }) {
    return showModalBottomSheet<WalkTrack>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TrackPickerSheet(
        tracks: tracks,
        selectedId: selectedId,
      ),
    );
  }

  String _label(WalkTrack t) {
    final fmt = DateFormat('M/d HH:mm');
    final start = fmt.format(t.startedAt);
    final pts = t.points.length;
    return '$start　$pts 点';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '再生する記録を選ぶ',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          if (tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('保存された記録がありません',
                  style: TextStyle(color: Colors.black45)),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tracks.length,
                itemBuilder: (_, i) {
                  final t = tracks[tracks.length - 1 - i]; // 新しい順
                  final isSelected = t.id == selectedId;
                  return ListTile(
                    leading: Icon(
                      Icons.history_rounded,
                      color: isSelected
                          ? const Color(0xFF2E7D32)
                          : Colors.black45,
                    ),
                    title: Text(
                      _label(t),
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Color(0xFF2E7D32))
                        : null,
                    onTap: () => Navigator.pop(context, t),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
