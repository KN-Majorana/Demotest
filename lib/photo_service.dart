import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// カメラ撮影・ギャラリー取得・保存サービス
class PhotoService {
  PhotoService._();

  static final _picker = ImagePicker();

  /// アプリの写真ディレクトリを返す（無ければ作成）。
  static Future<Directory> _photosDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(dir.path, 'photos'));
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }
    return photosDir;
  }

  /// カメラで撮影し、アプリの写真ディレクトリに保存する。
  /// キャンセルされた場合は null を返す。
  static Future<String?> takeAndSavePhoto() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (xFile == null) return null;

    final photosDir = await _photosDir();
    final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final destPath = p.join(photosDir.path, fileName);
    await File(xFile.path).copy(destPath);
    return destPath;
  }

  /// ギャラリーから1枚選択し、アプリの写真ディレクトリに保存する。
  /// キャンセルされた場合は null を返す。
  ///
  /// EXIF（GPS/撮影日時）を保持したいので imageQuality は指定しない
  /// （再エンコードでメタデータが失われるのを避けるため）。
  static Future<String?> pickFromGalleryAndSave() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: true,
    );
    if (xFile == null) return null;

    final photosDir = await _photosDir();
    final ext = p.extension(xFile.path).isNotEmpty
        ? p.extension(xFile.path)
        : '.jpg';
    final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}$ext';
    final destPath = p.join(photosDir.path, fileName);
    await File(xFile.path).copy(destPath);
    return destPath;
  }

  /// 撮影/選択したがピンを立てないと判断した写真ファイルを破棄する。
  /// （色が一致しなかった場合などに使用）
  static Future<void> deletePhotoFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 破棄失敗は無視（一時ファイルのため致命的でない）
    }
  }
}
