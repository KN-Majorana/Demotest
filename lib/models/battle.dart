/// 対戦（1v1 バトル）セッションのモデルと状態。
///
/// 時刻は比較の安定と実装簡略化のため epoch ミリ秒(int)で保持する。
/// （厳密なサーバ時刻運用が必要なら serverTimestamp へ差し替え可能。）
enum BattleStatus {
  pending,
  active,
  ended,
  resultShown,
  cleared,
  declined,
  expired,
  unknown,
}

BattleStatus battleStatusFromString(String? s) {
  switch (s) {
    case 'pending':
      return BattleStatus.pending;
    case 'active':
      return BattleStatus.active;
    case 'ended':
      return BattleStatus.ended;
    case 'result_shown':
      return BattleStatus.resultShown;
    case 'cleared':
      return BattleStatus.cleared;
    case 'declined':
      return BattleStatus.declined;
    case 'expired':
      return BattleStatus.expired;
    default:
      return BattleStatus.unknown;
  }
}

String battleStatusToString(BattleStatus s) {
  switch (s) {
    case BattleStatus.pending:
      return 'pending';
    case BattleStatus.active:
      return 'active';
    case BattleStatus.ended:
      return 'ended';
    case BattleStatus.resultShown:
      return 'result_shown';
    case BattleStatus.cleared:
      return 'cleared';
    case BattleStatus.declined:
      return 'declined';
    case BattleStatus.expired:
      return 'expired';
    case BattleStatus.unknown:
      return 'unknown';
  }
}

class Battle {
  final String id;
  final BattleStatus status;
  final String challengerUid;
  final String challengerName;
  final String opponentUid;
  final String opponentName;

  final DateTime? createdAt;
  final DateTime? expiresAt; // pending の応答期限
  final int timeLimitSec;
  final DateTime? startedAt;
  final DateTime? endsAt; // 予定終了時刻
  final DateTime? endedAt;
  final String? endedBy; // 'timeout' | 'forceEnd'

  final int? challengerColorId;
  final int? opponentColorId;

  final String? forceEndRequestBy;
  final DateTime? forceEndRequestAt;
  final String? resultCloseRequestBy;
  final DateTime? resultCloseRequestAt;

  final String? resultSnapshotUrl;

  const Battle({
    required this.id,
    required this.status,
    required this.challengerUid,
    required this.challengerName,
    required this.opponentUid,
    required this.opponentName,
    this.createdAt,
    this.expiresAt,
    this.timeLimitSec = 3600,
    this.startedAt,
    this.endsAt,
    this.endedAt,
    this.endedBy,
    this.challengerColorId,
    this.opponentColorId,
    this.forceEndRequestBy,
    this.forceEndRequestAt,
    this.resultCloseRequestBy,
    this.resultCloseRequestAt,
    this.resultSnapshotUrl,
  });

  bool isParticipant(String uid) =>
      uid == challengerUid || uid == opponentUid;

  bool isChallenger(String uid) => uid == challengerUid;

  String opponentUidFor(String uid) =>
      uid == challengerUid ? opponentUid : challengerUid;

  String opponentNameFor(String uid) =>
      uid == challengerUid ? opponentName : challengerName;

  String myNameFor(String uid) =>
      uid == challengerUid ? challengerName : opponentName;

  int? myColorId(String uid) =>
      uid == challengerUid ? challengerColorId : opponentColorId;

  int? opponentColorIdFor(String uid) =>
      uid == challengerUid ? opponentColorId : challengerColorId;

  /// pending が期限切れかどうか（クライアント側失効判定）。
  bool get isExpiredNow =>
      status == BattleStatus.pending &&
      expiresAt != null &&
      DateTime.now().isAfter(expiresAt!);

  /// active が予定終了時刻を過ぎているか。
  bool get isPastEnd =>
      status == BattleStatus.active &&
      endsAt != null &&
      DateTime.now().isAfter(endsAt!);

  /// 残り時間（active 用）。負なら Duration.zero。
  Duration remaining() {
    if (endsAt == null) return Duration.zero;
    final r = endsAt!.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  static DateTime? _dt(dynamic ms) => ms == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());

  factory Battle.fromMap(String id, Map<String, dynamic> m) {
    final ca = m['colorAssignment'] as Map<String, dynamic>?;
    return Battle(
      id: id,
      status: battleStatusFromString(m['status'] as String?),
      challengerUid: m['challengerUid'] as String? ?? '',
      challengerName: m['challengerName'] as String? ?? '挑戦者',
      opponentUid: m['opponentUid'] as String? ?? '',
      opponentName: m['opponentName'] as String? ?? '相手',
      createdAt: _dt(m['createdAt']),
      expiresAt: _dt(m['expiresAt']),
      timeLimitSec: (m['timeLimitSec'] as num?)?.toInt() ?? 3600,
      startedAt: _dt(m['startedAt']),
      endsAt: _dt(m['endsAt']),
      endedAt: _dt(m['endedAt']),
      endedBy: m['endedBy'] as String?,
      challengerColorId: (ca?['challengerColorId'] as num?)?.toInt(),
      opponentColorId: (ca?['opponentColorId'] as num?)?.toInt(),
      forceEndRequestBy: m['forceEndRequestBy'] as String?,
      forceEndRequestAt: _dt(m['forceEndRequestAt']),
      resultCloseRequestBy: m['resultCloseRequestBy'] as String?,
      resultCloseRequestAt: _dt(m['resultCloseRequestAt']),
      resultSnapshotUrl: m['resultSnapshotUrl'] as String?,
    );
  }
}
