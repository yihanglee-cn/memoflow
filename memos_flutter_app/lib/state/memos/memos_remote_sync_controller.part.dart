part of 'memos_providers.dart';

class RemoteSyncController extends SyncControllerBase {
  RemoteSyncController({
    required this.db,
    required this.api,
    required this.currentUserName,
    required this.syncStatusTracker,
    required this.syncQueueProgressTracker,
    required this.imageBedRepository,
    required this.attachmentPreprocessor,
    this.onRelationsSynced,
  }) : super(const AsyncValue.data(null));

  final AppDatabase db;
  final MemosApi api;
  final String currentUserName;
  final SyncStatusTracker syncStatusTracker;
  final SyncQueueProgressTracker syncQueueProgressTracker;
  final ImageBedSettingsRepository imageBedRepository;
  final AttachmentPreprocessor attachmentPreprocessor;
  final void Function(Set<String> memoUids)? onRelationsSynced;
  int _syncRunSeq = 0;
  bool _isDisposed = false;
  final String _controllerId =
      'remote_${DateTime.now().toUtc().millisecondsSinceEpoch}_${identityHashCode(Object())}';

  static const List<Duration> _retryBackoffSteps = <Duration>[
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 12),
    Duration(seconds: 24),
    Duration(seconds: 45),
  ];
  static const int _bulkOutboxTaskLogHeadCount = 3;
  static const int _bulkOutboxTaskLogEvery = 250;
  static const int _outboxProgressLogEvery = 200;
  static const Duration _slowOutboxTaskThreshold = Duration(seconds: 2);

  static int? _parseUserId(String userName) {
    final raw = userName.trim();
    if (raw.isEmpty) return null;
    final lastSegment = raw.contains('/') ? raw.split('/').last : raw;
    return int.tryParse(lastSegment);
  }

  String? get _creatorFilter {
    final id = _parseUserId(currentUserName);
    if (id == null) return null;
    return _buildCreatorFilterExpression(
      creatorId: id,
      useLegacyDialect: api.usesLegacySearchFilterDialect,
    );
  }

  String? get _memoParentName {
    final raw = currentUserName.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('users/')) return raw;
    final id = _parseUserId(raw);
    if (id == null) return null;
    return 'users/$id';
  }

  @override
  void dispose() {
    final queueSnapshot = syncQueueProgressTracker.snapshot;
    if (queueSnapshot.syncing) {
      syncQueueProgressTracker.markSyncFinished();
      LogManager.instance.info(
        'RemoteSync: controller_disposed_release_queue_lock',
        context: <String, Object?>{
          'controllerId': _controllerId,
          'queueCurrentOutboxId': queueSnapshot.currentOutboxId,
          'queueTotalTasks': queueSnapshot.totalTasks,
          'queueCompletedTasks': queueSnapshot.completedTasks,
        },
      );
    }
    LogManager.instance.info(
      'RemoteSync: controller_disposed',
      context: <String, Object?>{'controllerId': _controllerId},
    );
    _isDisposed = true;
    super.dispose();
  }

  @override
  Future<MemoSyncResult> syncNow() async {
    final runId =
        'run_${DateTime.now().toUtc().millisecondsSinceEpoch}_${++_syncRunSeq}';
    final queueSnapshot = syncQueueProgressTracker.snapshot;
    final globalSyncing = queueSnapshot.syncing;
    final stateLoading = _readStateLoadingSafely(runId: runId) ?? false;
    if (stateLoading || globalSyncing) {
      LogManager.instance.debug(
        'RemoteSync: sync_skipped_loading',
        context: <String, Object?>{
          'controllerId': _controllerId,
          'runId': runId,
          'stateLoading': stateLoading,
          'globalSyncing': globalSyncing,
          'queueCurrentOutboxId': queueSnapshot.currentOutboxId,
          'queueTotalTasks': queueSnapshot.totalTasks,
          'queueCompletedTasks': queueSnapshot.completedTasks,
          'queueOverallProgress': queueSnapshot.overallProgress,
        },
      );
      return const MemoSyncSkipped();
    }
    LogManager.instance.info(
      'RemoteSync: sync_start',
      context: <String, Object?>{
        'controllerId': _controllerId,
        'runId': runId,
        'effectiveServerVersion': api.effectiveServerVersion,
        'usesLegacyMemos': api.usesLegacyMemos,
        'requiresCreatorScopedList': api.requiresCreatorScopedListMemos,
      },
    );
    syncStatusTracker.markSyncStarted();
    await db.recoverOutboxRunningTasks();
    final totalPendingAtStart = await db.countOutboxPending();
    syncQueueProgressTracker.markSyncStarted(totalTasks: totalPendingAtStart);
    if (!_setStateSafely(
      const AsyncValue.loading(),
      runId: runId,
      stage: 'set_loading',
    )) {
      syncQueueProgressTracker.markSyncFinished();
      return const MemoSyncSkipped();
    }
    var outboxBlocked = false;
    final next = await AsyncValue.guard(() async {
      await api.ensureServerHintsLoaded();
      if (_isDisposed) {
        _logSyncAbortDisposed(runId: runId, stage: 'after_ensure_server_hints');
        return;
      }
      outboxBlocked = await _processOutbox();
      if (_isDisposed) {
        _logSyncAbortDisposed(runId: runId, stage: 'after_process_outbox');
        return;
      }
      final allowPrivateVisibilityPrune =
          await _allowPrivateVisibilityPruneForCurrentServer();
      if (_isDisposed) {
        _logSyncAbortDisposed(
          runId: runId,
          stage: 'after_resolve_visibility_prune',
        );
        return;
      }
      await _syncStateMemos(
        runId: runId,
        state: 'NORMAL',
        allowPrivateVisibilityPrune: allowPrivateVisibilityPrune,
      );
      if (_isDisposed) {
        _logSyncAbortDisposed(
          runId: runId,
          stage: 'after_sync_normal_state',
          syncState: 'NORMAL',
        );
        return;
      }
      await _syncStateMemos(
        runId: runId,
        state: 'ARCHIVED',
        allowPrivateVisibilityPrune: allowPrivateVisibilityPrune,
      );
    });
    if (_isDisposed) {
      _logSyncAbortDisposed(runId: runId, stage: 'after_guard_before_commit');
      syncQueueProgressTracker.markSyncFinished();
      return const MemoSyncSkipped();
    }
    if (!_setStateSafely(next, runId: runId, stage: 'set_result')) {
      syncQueueProgressTracker.markSyncFinished();
      return const MemoSyncSkipped();
    }
    if (next.hasError) {
      syncStatusTracker.markSyncFailed(next.error!);
      LogManager.instance.warn(
        'RemoteSync: sync_failed',
        error: next.error,
        stackTrace: next.stackTrace,
        context: <String, Object?>{
          'controllerId': _controllerId,
          'runId': runId,
          'outboxBlocked': outboxBlocked,
        },
      );
    } else {
      syncStatusTracker.markSyncSuccess();
      LogManager.instance.info(
        'RemoteSync: sync_success',
        context: <String, Object?>{
          'controllerId': _controllerId,
          'runId': runId,
          'outboxBlocked': outboxBlocked,
        },
      );
    }
    syncQueueProgressTracker.markSyncFinished();
    if (next.hasError) {
      return MemoSyncFailure(_buildSyncError(next.error!));
    }
    if (outboxBlocked) {
      return MemoSyncFailure(_outboxBlockedError());
    }
    return const MemoSyncSuccess();
  }

  bool? _readStateLoadingSafely({required String runId}) {
    try {
      return state.isLoading;
    } catch (error, stackTrace) {
      LogManager.instance.warn(
        'RemoteSync: read_state_loading_failed',
        error: error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'controllerId': _controllerId,
          'runId': runId,
        },
      );
      return null;
    }
  }

  bool _setStateSafely(
    AsyncValue<void> next, {
    required String runId,
    required String stage,
  }) {
    if (_isDisposed) {
      _logSyncAbortDisposed(runId: runId, stage: 'state_set_skipped_$stage');
      return false;
    }
    try {
      state = next;
      return true;
    } catch (error, stackTrace) {
      LogManager.instance.warn(
        'RemoteSync: set_state_failed',
        error: error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'controllerId': _controllerId,
          'runId': runId,
          'stage': stage,
        },
      );
      return false;
    }
  }

  void _logSyncAbortDisposed({
    required String runId,
    required String stage,
    String? syncState,
  }) {
    LogManager.instance.info(
      'RemoteSync: sync_aborted_disposed',
      context: <String, Object?>{
        'controllerId': _controllerId,
        'runId': runId,
        'stage': stage,
        if (syncState != null) 'syncState': syncState,
      },
    );
  }
}
