import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// Cloud Storage への写真アップロードを担うサービス。
class StorageUploadService {
  StorageUploadService._();

  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// ローカル写真をアップロードしてダウンロード URL を返す。
  ///
  /// 保存パス: photos/{ownerUid}/{photoId}.jpg
  /// 同じ photoId なら上書き（冪等）になる。
  static Future<String> uploadPhoto({
    required String ownerUid,
    required String photoId,
    required String localPath,
  }) async {
    final file = File(localPath);
    final ref = _storage.ref('photos/$ownerUid/$photoId.jpg');
    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return task.ref.getDownloadURL();
  }

  /// アップロード済みの写真を Storage から削除する（存在しなくても無視）。
  static Future<void> deletePhoto({
    required String ownerUid,
    required String photoId,
  }) async {
    try {
      await _storage.ref('photos/$ownerUid/$photoId.jpg').delete();
    } catch (_) {
      // 未アップロード / 既に削除済みなどは無視
    }
  }
}
