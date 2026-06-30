import 'package:flutter/material.dart';

import 'color_extraction.dart';
import 'models/polygon.dart';

enum PolygonChoiceKind { createNew, addExisting }

/// 機能3 の選択結果。
class PolygonChoiceResult {
  final PolygonChoiceKind kind;

  /// addExisting のとき選ばれた多角形
  final WalkPolygon? target;

  const PolygonChoiceResult.createNew()
      : kind = PolygonChoiceKind.createNew,
        target = null;

  const PolygonChoiceResult.addExisting(this.target)
      : kind = PolygonChoiceKind.addExisting;
}

/// 機能3：撮影直後に「新規作成 / 既存に頂点追加」を選ばせる BottomSheet。
class PolygonChoiceSheet {
  /// [existingPolygons] は自分の確定済み多角形。空でも新規作成は選べる。
  static Future<PolygonChoiceResult?> show(
    BuildContext context, {
    required List<WalkPolygon> existingPolygons,
  }) {
    return showModalBottomSheet<PolygonChoiceResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ChoiceBody(existingPolygons: existingPolygons),
    );
  }
}

class _ChoiceBody extends StatefulWidget {
  final List<WalkPolygon> existingPolygons;
  const _ChoiceBody({required this.existingPolygons});

  @override
  State<_ChoiceBody> createState() => _ChoiceBodyState();
}

class _ChoiceBodyState extends State<_ChoiceBody> {
  bool _picking = false; // 既存多角形の選択ステージか

  @override
  Widget build(BuildContext context) {
    final confirmed =
        widget.existingPolygons.where((p) => p.confirmed).toList()
          ..sort((a, b) => (b.createdAt ?? DateTime(0))
              .compareTo(a.createdAt ?? DateTime(0)));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: _picking
              ? _buildPickExisting(confirmed)
              : _buildTopChoice(confirmed),
        ),
      ),
    );
  }

  Widget _buildTopChoice(List<WalkPolygon> confirmed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'この写真をどうしますか？',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            const PolygonChoiceResult.createNew(),
          ),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('新たに多角形を作る'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: confirmed.isEmpty
              ? null
              : () => setState(() => _picking = true),
          icon: const Icon(Icons.add_to_photos_outlined),
          label: Text(
            confirmed.isEmpty
                ? '既存の多角形に追加（まだありません）'
                : '既存の多角形に頂点を追加する',
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('キャンセル'),
        ),
      ],
    );
  }

  Widget _buildPickExisting(List<WalkPolygon> confirmed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _picking = false),
              icon: const Icon(Icons.arrow_back),
            ),
            const Text(
              '追加先の多角形を選択',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '選んだ多角形の色と写真の色が一致した場合のみ追加されます。',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: confirmed.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final poly = confirmed[i];
              final c = poly.colorId < colorPalette24.length
                  ? colorPalette24[poly.colorId]
                  : const ColorRGB(128, 128, 128);
              final name = poly.colorId < colorNames24.length
                  ? colorNames24[poly.colorId]
                  : '';
              final created = poly.createdAt;
              final timeLabel = created == null
                  ? ''
                  : '${created.month}/${created.day} '
                      '${created.hour.toString().padLeft(2, '0')}:'
                      '${created.minute.toString().padLeft(2, '0')}';
              return ListTile(
                leading: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(c.r, c.g, c.b, 1.0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                ),
                title: Text('$name の多角形'),
                subtitle: Text('作成: $timeLabel ・ ${poly.photoIds.length}枚'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(
                  context,
                  PolygonChoiceResult.addExisting(poly),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
