import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/models/local_memo.dart';
import '../system/database_provider.dart';
import '../system/reminder_scheduler.dart';
import 'memo_timeline_provider.dart';

final memoDeleteServiceProvider = Provider<MemoDeleteService>((ref) {
  return MemoDeleteService(ref);
});

class MemoDeleteService {
  MemoDeleteService(this._ref);

  final Ref _ref;

  Future<void> deleteMemo(
    LocalMemo memo, {
    void Function()? onMovedToRecycleBin,
  }) async {
    final memoUid = memo.uid.trim();
    if (memoUid.isEmpty) return;

    final db = _ref.read(databaseProvider);
    final timelineService = _ref.read(memoTimelineServiceProvider);
    await timelineService.moveMemoToRecycleBin(memo);
    onMovedToRecycleBin?.call();

    final shouldCleanupCreateDraftAttachments = await db
        .hasPendingOutboxTaskForMemo(memoUid, types: const {'create_memo'});
    final draftAttachmentNames = shouldCleanupCreateDraftAttachments
        ? memo.attachments
              .map((attachment) => attachment.name.trim())
              .where((name) => name.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    await db.upsertMemoDeleteTombstone(
      memoUid: memoUid,
      state: AppDatabase.memoDeleteTombstoneStatePendingRemoteDelete,
    );
    await db.deleteOutboxForMemo(memoUid);
    for (final attachmentName in draftAttachmentNames) {
      await db.enqueueOutbox(
        type: 'delete_attachment',
        payload: {'attachment_name': attachmentName, 'memo_uid': memoUid},
      );
    }
    await db.deleteMemoByUid(memoUid);
    await db.enqueueOutbox(
      type: 'delete_memo',
      payload: {'uid': memoUid, 'force': false},
    );
    await _ref.read(reminderSchedulerProvider).rescheduleAll();
  }
}
