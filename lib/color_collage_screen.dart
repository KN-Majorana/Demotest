import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

import 'color_extraction.dart';
import 'photo_pin.dart';

// ─────────────────────────────────────────
// Stories レイアウト定義（9:16）
// スロット: [left%, top%, width%, height%]
// ─────────────────────────────────────────

const _storiesLayouts = <int, List<List<double>>>{
  3: [
    [0.00, 0.00, 1.00, 0.56],
    [0.00, 0.56, 0.50, 0.44],
    [0.50, 0.56, 0.50, 0.44],
  ],
  4: [
    [0.00, 0.00, 0.50, 0.50],
    [0.50, 0.00, 0.50, 0.50],
    [0.00, 0.50, 0.50, 0.50],
    [0.50, 0.50, 0.50, 0.50],
  ],
  5: [
    [0.000, 0.00, 0.500, 0.44],
    [0.500, 0.00, 0.500, 0.44],
    [0.000, 0.44, 0.334, 0.56],
    [0.334, 0.44, 0.333, 0.56],
    [0.667, 0.44, 0.333, 0.56],
  ],
  6: [
    [0.00, 0.000, 0.50, 0.334],
    [0.50, 0.000, 0.50, 0.334],
    [0.00, 0.334, 0.50, 0.333],
    [0.50, 0.334, 0.50, 0.333],
    [0.00, 0.667, 0.50, 0.333],
    [0.50, 0.667, 0.50, 0.333],
  ],
  7: [
    [0.000, 0.000, 0.500, 0.334],
    [0.500, 0.000, 0.500, 0.334],
    [0.000, 0.334, 0.500, 0.333],
    [0.500, 0.334, 0.500, 0.333],
    [0.000, 0.667, 0.334, 0.333],
    [0.334, 0.667, 0.333, 0.333],
    [0.667, 0.667, 0.333, 0.333],
  ],
  8: [
    [0.000, 0.000, 0.334, 0.334],
    [0.334, 0.000, 0.333, 0.334],
    [0.667, 0.000, 0.333, 0.334],
    [0.000, 0.334, 0.334, 0.333],
    [0.334, 0.334, 0.333, 0.333],
    [0.667, 0.334, 0.333, 0.333],
    [0.000, 0.667, 0.500, 0.333],
    [0.500, 0.667, 0.500, 0.333],
  ],
  9: [
    [0.000, 0.000, 0.334, 0.334],
    [0.334, 0.000, 0.333, 0.334],
    [0.667, 0.000, 0.333, 0.334],
    [0.000, 0.334, 0.334, 0.333],
    [0.334, 0.334, 0.333, 0.333],
    [0.667, 0.334, 0.333, 0.333],
    [0.000, 0.667, 0.334, 0.333],
    [0.334, 0.667, 0.333, 0.333],
    [0.667, 0.667, 0.333, 0.333],
  ],
};

List<List<double>> _layoutFor(int count) {
  final c = count.clamp(3, 9);
  return _storiesLayouts[c] ?? _storiesLayouts[6]!;
}

/// 隙間なし（シームレス）。小数誤差による髪の毛1px隙間を防ぐため
/// 右・下エッジでない辺は 0.5px だけはみ出す。
Rect _slotToRect(List<double> s, double w, double h) {
  const eps = 0.001;
  const overshoot = 0.5;
  final isRight  = s[0] + s[2] > 1 - eps;
  final isBottom = s[1] + s[3] > 1 - eps;
  return Rect.fromLTRB(
    s[0] * w,
    s[1] * h,
    (s[0] + s[2]) * w + (isRight  ? 0 : overshoot),
    (s[1] + s[3]) * h + (isBottom ? 0 : overshoot),
  );
}

// ─────────────────────────────────────────
// 画面
// ─────────────────────────────────────────

class ColorCollageScreen extends StatelessWidget {
  final List<PhotoPin> photoPins;
  const ColorCollageScreen({super.key, required this.photoPins});

  Map<int, List<PhotoPin>> _buildColorGroups() {
    final Map<int, List<PhotoPin>> groups = {};
    for (final pin in photoPins) {
      for (final id in pin.colorIds) {
        groups.putIfAbsent(id, () => []).add(pin);
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final colorGroups = _buildColorGroups();
    final sortedEntries = colorGroups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text(
          'COLOR HUNTING',
          style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: sortedEntries.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.palette_outlined, size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text(
                    '写真を撮影すると\nカラーコレクションが始まります',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              itemCount: sortedEntries.length,
              itemBuilder: (_, index) {
                final entry = sortedEntries[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: _ColorCollageCard(colorId: entry.key, pins: entry.value),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────
// カード
// ─────────────────────────────────────────

class _ColorCollageCard extends StatefulWidget {
  final int colorId;
  final List<PhotoPin> pins;
  const _ColorCollageCard({required this.colorId, required this.pins});

  @override
  State<_ColorCollageCard> createState() => _ColorCollageCardState();
}

class _ColorCollageCardState extends State<_ColorCollageCard> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _saving = false;

  /// 現在のレイアウトスロット数（3〜9）
  late int _layoutCount;

  /// スロットごとの写真インデックス（widget.pins のインデックス）
  late List<int> _slotPhotoIndices;

  bool get _achieved => widget.pins.length >= 3;

  Color get _paletteColor {
    final c = colorPalette24[widget.colorId];
    return Color.fromRGBO(c.r, c.g, c.b, 1);
  }

  String get _colorName => colorNames24[widget.colorId];

  @override
  void initState() {
    super.initState();
    _layoutCount = widget.pins.length.clamp(3, 9);
    _resetSlots();
  }

  /// スロット数に合わせてデフォルト割り当て（0,1,2,… と順に埋め、足りなければ繰り返す）
  void _resetSlots() {
    _slotPhotoIndices = List.generate(
      _layoutCount,
      (i) => i % widget.pins.length,
    );
  }

  void _changeLayout(int count) {
    setState(() {
      // 既存の割り当てを可能な限り引き継ぐ
      final prev = List.of(_slotPhotoIndices);
      _layoutCount = count;
      _slotPhotoIndices = List.generate(
        count,
        (i) => i < prev.length ? prev[i] : i % widget.pins.length,
      );
    });
  }

  void _showPhotoPicker(int slotIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PhotoPickerSheet(
        pins: widget.pins,
        selectedIndex: _slotPhotoIndices[slotIndex],
        paletteColor: _paletteColor,
        slotIndex: slotIndex,
        onSelect: (photoIndex) {
          Navigator.pop(context);
          setState(() => _slotPhotoIndices[slotIndex] = photoIndex);
        },
      ),
    );
  }

  Future<void> _saveToGallery() async {
    setState(() => _saving = true);
    try {
      final status = await Permission.photos.request();
      if (!status.isGranted && !status.isLimited) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('写真ライブラリへのアクセスを許可してください')),
          );
        }
        return;
      }

      final boundary = _repaintKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final result = await ImageGallerySaver.saveImage(
        byteData.buffer.asUint8List(),
        name: 'hunting_${_colorName}_${DateTime.now().millisecondsSinceEpoch}',
        isReturnImagePathOfIOS: false,
      );

      if (mounted) {
        final success = result['isSuccess'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? 'カメラロールに保存しました' : '保存に失敗しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── ヘッダー ───
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(color: _paletteColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                _colorName.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold,
                  fontSize: 13, letterSpacing: 3,
                ),
              ),
              const Spacer(),
              Text(
                _achieved ? '${widget.pins.length} collected ✓' : '${widget.pins.length} / 3',
                style: TextStyle(
                  color: _achieved ? _paletteColor : Colors.white38,
                  fontSize: 12, fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // ─── レイアウトピッカー（達成後のみ）───
        if (_achieved) ...[
          _LayoutPicker(
            selected: _layoutCount,
            paletteColor: _paletteColor,
            onSelect: _changeLayout,
          ),
          const SizedBox(height: 8),
        ],

        // ─── コラージュ本体 ───
        RepaintBoundary(
          key: _repaintKey,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _achieved
                ? _StoriesCollage(
                    key: ValueKey(_layoutCount),
                    slotPins: _slotPhotoIndices
                        .map((i) => widget.pins[i])
                        .toList(),
                    slotPinIndices: List.of(_slotPhotoIndices),
                    onSlotLongPress: _showPhotoPicker,
                  )
                : _IncompletePreview(
                    pins: widget.pins,
                    paletteColor: _paletteColor,
                    colorName: _colorName,
                  ),
          ),
        ),

        // ─── 操作ヒント（達成後のみ）───
        if (_achieved) ...[
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pinch_outlined, size: 13, color: Colors.white30),
              SizedBox(width: 4),
              Text(
                'ピンチ / ドラッグで調整　ダブルタップでリセット　長押しで写真を変更',
                style: TextStyle(color: Colors.white30, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ─── 保存ボタン ───
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _saveToGallery,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _paletteColor, width: 1.5),
                foregroundColor: _paletteColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _saving
                  ? SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _paletteColor),
                    )
                  : const Icon(Icons.save_alt, size: 16),
              label: Text(
                _saving ? '保存中...' : 'SAVE TO CAMERA ROLL',
                style: const TextStyle(letterSpacing: 1.5, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          Text(
            'あと ${3 - widget.pins.length} 枚集めるとコラージュが完成します',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────
// レイアウトピッカー
// ─────────────────────────────────────────

class _LayoutPicker extends StatelessWidget {
  final int selected;
  final Color paletteColor;
  final void Function(int count) onSelect;

  const _LayoutPicker({
    required this.selected,
    required this.paletteColor,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 7, // 3〜9
        itemBuilder: (_, i) {
          final count = i + 3;
          final isSelected = count == selected;
          return GestureDetector(
            onTap: () => onSelect(count),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? paletteColor : Colors.white24,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(6),
                color: isSelected
                    ? paletteColor.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
              child: _LayoutThumbnail(
                count: count,
                isSelected: isSelected,
                color: paletteColor,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// レイアウトの構造をミニチュアで表示するウィジェット
class _LayoutThumbnail extends StatelessWidget {
  final int count;
  final bool isSelected;
  final Color color;

  const _LayoutThumbnail({
    required this.count,
    required this.isSelected,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final slots = _layoutFor(count);
    const tw = 22.0;
    const th = 38.0; // ≈ 9:16

    return SizedBox(
      width: tw,
      height: th,
      child: Stack(
        children: slots.map((s) {
          const margin = 0.8;
          return Positioned(
            left:   s[0] * tw + margin,
            top:    s[1] * th + margin,
            width:  s[2] * tw - margin * 2,
            height: s[3] * th - margin * 2,
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.75)
                    : Colors.white38,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────
// Stories コラージュ（ステートレス外殻）
// 各セルは _InteractiveCell（ステートフル）で独立管理
// ─────────────────────────────────────────

class _StoriesCollage extends StatelessWidget {
  final List<PhotoPin> slotPins;
  final List<int> slotPinIndices; // セルのキーに使用
  final void Function(int slotIndex)? onSlotLongPress;

  const _StoriesCollage({
    super.key,
    required this.slotPins,
    required this.slotPinIndices,
    this.onSlotLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final slots = _layoutFor(slotPins.length);

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return Stack(
            children: [
              const ColoredBox(color: Colors.black, child: SizedBox.expand()),
              for (int i = 0; i < slotPins.length && i < slots.length; i++)
                Builder(builder: (_) {
                  final r = _slotToRect(slots[i], w, h);
                  return Positioned(
                    left: r.left, top: r.top,
                    width: r.width, height: r.height,
                    child: _InteractiveCell(
                      // キーにスロット番号と写真インデックスを含めることで
                      // 写真が差し替わったとき自動的に transform がリセットされる
                      key: ValueKey('$i-${slotPinIndices[i]}'),
                      pin: slotPins[i],
                      onLongPress: onSlotLongPress != null
                          ? () => onSlotLongPress!(i)
                          : null,
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────
// 各セルのインタラクティブウィジェット
// ─────────────────────────────────────────

class _InteractiveCell extends StatefulWidget {
  final PhotoPin pin;
  final VoidCallback? onLongPress;

  const _InteractiveCell({
    super.key,
    required this.pin,
    this.onLongPress,
  });

  @override
  State<_InteractiveCell> createState() => _InteractiveCellState();
}

class _InteractiveCellState extends State<_InteractiveCell> {
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  void _reset() => setState(() {
    _scale = 1.0;
    _offset = Offset.zero;
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return GestureDetector(
          onScaleStart: (details) {
            _startScale  = _scale;
            _startOffset = _offset;
            _startFocal  = details.focalPoint;
          },
          onScaleUpdate: (details) {
            final newScale = (_startScale * details.scale).clamp(1.0, 6.0);

            final focalDelta    = details.focalPoint - _startFocal;
            final focalCentered = _startFocal - Offset(w / 2, h / 2);
            final zoomShift     = focalCentered * (1 - details.scale);
            final rawOffset     = _startOffset + focalDelta + zoomShift;

            final maxDx = w * (newScale - 1) / 2;
            final maxDy = h * (newScale - 1) / 2;

            setState(() {
              _scale  = newScale;
              _offset = Offset(
                rawOffset.dx.clamp(-maxDx, maxDx),
                rawOffset.dy.clamp(-maxDy, maxDy),
              );
            });
          },
          onDoubleTap: _reset,
          onLongPress: widget.onLongPress,
          child: ClipRect(
            child: Transform(
              transform: Matrix4.identity()
                // ignore: deprecated_member_use
                ..translate(_offset.dx, _offset.dy)
                // ignore: deprecated_member_use
                ..scale(_scale),
              alignment: Alignment.center,
              child: SizedBox(
                width: w,
                height: h,
                child: widget.pin.imagePath.isNotEmpty
                    ? Image.file(File(widget.pin.imagePath), fit: BoxFit.cover)
                    : ColoredBox(
                        color: Colors.grey.shade900,
                        child: const SizedBox.expand(),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────
// 写真ピッカーシート（ボトムシート）
// ─────────────────────────────────────────

class _PhotoPickerSheet extends StatelessWidget {
  final List<PhotoPin> pins;
  final int selectedIndex;
  final Color paletteColor;
  final int slotIndex;
  final void Function(int photoIndex) onSelect;

  const _PhotoPickerSheet({
    required this.pins,
    required this.selectedIndex,
    required this.paletteColor,
    required this.slotIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // グラブハンドル
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            'スロット ${slotIndex + 1} の写真を選択',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: pins.length,
              itemBuilder: (_, i) {
                final isSelected = i == selectedIndex;
                return GestureDetector(
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 82,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected ? paletteColor : Colors.transparent,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(pins[i].imagePath),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// 未完成プレビュー（9:16）
// ─────────────────────────────────────────

class _IncompletePreview extends StatelessWidget {
  final List<PhotoPin> pins;
  final Color paletteColor;
  final String colorName;

  const _IncompletePreview({
    required this.pins,
    required this.paletteColor,
    required this.colorName,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.grey.shade900, child: const SizedBox.expand()),
          if (pins.isNotEmpty && pins.first.imagePath.isNotEmpty)
            Opacity(
              opacity: 0.25,
              child: Image.file(File(pins.first.imagePath), fit: BoxFit.cover),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, color: paletteColor, size: 40),
                const SizedBox(height: 10),
                Text(
                  colorName.toUpperCase(),
                  style: TextStyle(
                    color: paletteColor, fontSize: 18,
                    fontWeight: FontWeight.w900, letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${3 - pins.length} more to unlock',
                  style: const TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
