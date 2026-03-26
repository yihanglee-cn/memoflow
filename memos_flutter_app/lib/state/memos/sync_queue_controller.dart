import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync/sync_request.dart';
import '../../application/sync/sync_types.dart';
import '../../data/db/app_database.dart';
import '../system/database_provider.dart';
import '../sync/sync_coordinator_provider.dart';
import 'sync_queue_models.dart';

final syncQueueControllerProvider = Provider<SyncQueueController>((ref) {
  return SyncQueueController(ref);
});

class SyncQueueController {
  SyncQueueController(this._ref);

  final Ref _ref;

  Future<void> deleteItem(SyncQueueItem item) async {
    final db = _ref.read(databaseProvider);
    final memoUid = item.memoUid?.trim();
    if (memoUid != null && memoUid.isNotEmpty) {
      final tombstoneState = await db.getMemoDeleteTombstoneState(memoUid);
      if (item.type == 'delete_memo' && tombstoneState != null) {
        await db.upsertMemoDeleteTombstone(
          memoUid: memoUid,
          state: AppDatabase.memoDeleteTombstoneStateLocalOnly,
        );
      }
      await db.deleteOutbox(item.id);
      if (item.type == 'upload_attachment' && item.attachmentUid != null) {
        await db.removePendingAttachmentPlaceholder(
          memoUid: memoUid,
          attachmentUid: item.attachmentUid!,
        );
      }
      await _clearMemoSyncErrorIfIdle(db, memoUid);
      return;
    }

    await db.deleteOutbox(item.id);
  }

  Future<void> retryItem(SyncQueueItem item) async {
    final db = _ref.read(databaseProvider);
    final memoUid = item.memoUid?.trim();
    if (memoUid != null && memoUid.isNotEmpty) {
      await db.retryOutboxErrors(memoUid: memoUid);
      return;
    }
    await db.retryOutboxErrors();
  }

  Future<SyncRunResult> requestSync() async {
    return _ref
        .read(syncCoordinatorProvider.notifier)
        .requestSync(
          const SyncRequest(
            kind: SyncRequestKind.memos,
            reason: SyncRequestReason.manual,
          ),
        );
  }

  Future<void> _clearMemoSyncErrorIfIdle(AppDatabase db, String memoUid) async {
    final trimmed = memoUid.trim();
    if (trimmed.isEmpty) return;
    final pending = await db.listPendingOutboxMemoUids();
    if (pending.contains(trimmed)) return;
    await db.updateMemoSyncState(trimmed, syncState: 0, lastError: null);
  }
}
