part of 'memos_providers.dart';

extension _RemoteSyncOutbox on RemoteSyncController {
  Future<bool> _processOutbox() async {
    var processedCount = 0;
    var successCount = 0;
    var failedCount = 0;
    final typeCounts = <String, int>{};
    String? blockedType;
    String? blockedReason;
    while (true) {
      final headItems = await db.listOutboxPending(limit: 1);
      if (headItems.isEmpty) {
        LogManager.instance.info(
          'RemoteSync outbox: summary',
          context: <String, Object?>{
            'processed': processedCount,
            'succeeded': successCount,
            'failed': failedCount,
            'blocked': false,
            if (typeCounts.isNotEmpty) 'typeCounts': typeCounts,
          },
        );
        return false;
      }

      final head = headItems.first;
      final headId = head['id'] as int?;
      final headType = head['type'] as String?;
      final headState =
          (head['state'] as int?) ?? AppDatabase.outboxStatePending;
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final retryAtRaw = head['retry_at'];
      final retryAtMs = switch (retryAtRaw) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v.trim()),
        _ => null,
      };
      if (headId == null || headType == null) continue;
      if (headState == AppDatabase.outboxStateError) {
        blockedType = headType;
        blockedReason = 'error_head';
        break;
      }
      if (headState == AppDatabase.outboxStateRetry &&
          retryAtMs != null &&
          retryAtMs > nowMs) {
        blockedType = headType;
        blockedReason = 'retry_waiting';
        break;
      }
      if (headState == AppDatabase.outboxStateRunning) {
        await db.recoverOutboxRunningTasks();
        continue;
      }

      final row = await db.claimOutboxTaskById(headId, nowMs: nowMs);
      if (row == null) continue;
      final id = row['id'] as int?;
      final type = row['type'] as String?;
      final payloadRaw = row['payload'] as String?;
      final attemptsSoFar = (row['attempts'] as int?) ?? 0;
      if (id == null || type == null || payloadRaw == null) continue;

      Map<String, dynamic> payload;
      try {
        payload = (jsonDecode(payloadRaw) as Map).cast<String, dynamic>();
      } catch (e) {
        await db.markOutboxError(id, error: 'Invalid payload: $e');
        processedCount++;
        failedCount++;
        typeCounts[type] = (typeCounts[type] ?? 0) + 1;
        LogManager.instance.warn(
          'RemoteSync outbox: invalid_payload',
          error: e,
          context: <String, Object?>{'id': id, 'type': type},
        );
        _maybeLogOutboxProgress(
          processedCount: processedCount,
          successCount: successCount,
          failedCount: failedCount,
          typeCounts: typeCounts,
          currentType: type,
        );
        syncQueueProgressTracker.updateCompletedTasks(
          successCount + failedCount,
        );
        blockedType = type;
        blockedReason = 'invalid_payload';
        break;
      }

      processedCount++;
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
      final memoUid = _outboxMemoUid(type, payload);
      final shouldLogTaskDetail = _shouldLogOutboxTaskDetail(
        type: type,
        processedCount: processedCount,
      );
      if (shouldLogTaskDetail) {
        LogManager.instance.debug(
          'RemoteSync outbox: task_start',
          context: <String, Object?>{
            'id': id,
            'type': type,
            if (memoUid != null && memoUid.isNotEmpty) 'memoUid': memoUid,
          },
        );
      }

      var shouldStop = false;
      final isUploadTask = type == 'upload_attachment';
      final taskStartAt = DateTime.now();
      syncQueueProgressTracker.markTaskStarted(id);
      final suppressDeletedMemoTask =
          memoUid != null &&
          memoUid.isNotEmpty &&
          type != 'delete_memo' &&
          type != 'delete_attachment' &&
          await db.hasMemoDeleteMarker(memoUid);
      if (suppressDeletedMemoTask) {
        await db.markOutboxDone(id);
        await db.deleteOutbox(id);
        successCount++;
        if (isUploadTask) {
          await syncQueueProgressTracker.markTaskCompleted(outboxId: id);
        }
        syncQueueProgressTracker.clearCurrentTask(outboxId: id);
        final elapsedMs = DateTime.now().difference(taskStartAt).inMilliseconds;
        LogManager.instance.info(
          'RemoteSync outbox: discard_deleted_memo_task',
          context: <String, Object?>{
            'id': id,
            'type': type,
            'memoUid': memoUid,
            'elapsedMs': elapsedMs,
          },
        );
        _maybeLogOutboxProgress(
          processedCount: processedCount,
          successCount: successCount,
          failedCount: failedCount,
          typeCounts: typeCounts,
          currentType: type,
        );
        syncQueueProgressTracker.updateCompletedTasks(
          successCount + failedCount,
        );
        continue;
      }
      try {
        switch (type) {
          case 'create_memo':
            final uid = await _handleCreateMemo(payload);
            final hasAttachments = payload['has_attachments'] as bool? ?? false;
            if (uid != null && uid.isNotEmpty) {
              final hasFollowUpOutbox =
                  hasAttachments &&
                  await db.hasPendingOutboxTaskForMemo(
                    uid,
                    types: const {'upload_attachment', 'update_memo'},
                  );
              if (!hasFollowUpOutbox) {
                await db.updateMemoSyncState(uid, syncState: 0);
              }
            }
            await db.markOutboxDone(id);
            await db.deleteOutbox(id);
            break;
          case 'update_memo':
            await _handleUpdateMemo(payload);
            final uid = payload['uid'] as String?;
            final hasPendingAttachments =
                payload['has_pending_attachments'] as bool? ?? false;
            if (!hasPendingAttachments && uid != null && uid.isNotEmpty) {
              await db.updateMemoSyncState(uid, syncState: 0);
            }
            await db.markOutboxDone(id);
            await db.deleteOutbox(id);
            break;
          case 'delete_memo':
            await _handleDeleteMemo(payload);
            final uid = payload['uid'] as String?;
            if (uid != null && uid.trim().isNotEmpty) {
              await db.deleteMemoDeleteTombstone(uid);
            }
            await db.markOutboxDone(id);
            await db.deleteOutbox(id);
            break;
          case 'upload_attachment':
            final isFinalized = await _handleUploadAttachment(
              payload,
              currentOutboxId: id,
            );
            final memoUid = payload['memo_uid'] as String?;
            if (isFinalized && memoUid != null && memoUid.isNotEmpty) {
              await db.updateMemoSyncState(memoUid, syncState: 0);
            }
            await db.markOutboxDone(id);
            await db.deleteOutbox(id);
            break;
          case 'delete_attachment':
            await _handleDeleteAttachment(payload);
            final memoUid = payload['memo_uid'] as String?;
            if (memoUid != null && memoUid.isNotEmpty) {
              final pendingUploads = await _countPendingAttachmentUploads(
                memoUid,
              );
              if (pendingUploads <= 0) {
                await db.updateMemoSyncState(memoUid, syncState: 0);
              }
            }
            await db.markOutboxDone(id);
            await db.deleteOutbox(id);
            break;
          case 'submit_log_report':
            LogManager.instance.info(
              'RemoteSync outbox: submit_log_report_discarded',
              context: <String, Object?>{
                'id': id,
                'reason': 'feature_disabled',
              },
            );
            await db.markOutboxDone(id);
            await db.deleteOutbox(id);
            break;
          default:
            throw StateError('Unknown op type: $type');
        }
        successCount++;
        final elapsedMs = DateTime.now().difference(taskStartAt).inMilliseconds;
        final isSlowTask =
            elapsedMs >=
            RemoteSyncController._slowOutboxTaskThreshold.inMilliseconds;
        if (shouldLogTaskDetail || isSlowTask) {
          LogManager.instance.debug(
            'RemoteSync outbox: task_done',
            context: <String, Object?>{
              'id': id,
              'type': type,
              if (memoUid != null && memoUid.isNotEmpty) 'memoUid': memoUid,
              'elapsedMs': elapsedMs,
              if (isSlowTask) 'slow': true,
            },
          );
        }
      } catch (e) {
        failedCount++;
        final elapsedMs = DateTime.now().difference(taskStartAt).inMilliseconds;
        final transientNetworkError =
            e is DioException && _isTransientOutboxNetworkError(e);
        final memoError = e is DioException
            ? _summarizeHttpError(e)
            : SyncError(
                code: SyncErrorCode.unknown,
                retryable: false,
                message: e.toString(),
              );
        final outboxError = e is DioException
            ? _detailHttpError(e)
            : e.toString();
        if (transientNetworkError) {
          final delay = _retryDelayForOutboxAttempt(attemptsSoFar);
          final retryAt =
              DateTime.now().toUtc().millisecondsSinceEpoch +
              delay.inMilliseconds;
          await db.markOutboxRetryScheduled(
            id,
            error: outboxError,
            retryAtMs: retryAt,
          );
          blockedReason = 'retry_scheduled';
          if (memoUid != null && memoUid.isNotEmpty) {
            await db.updateMemoSyncState(memoUid, syncState: 1);
          }
        } else {
          await db.markOutboxError(id, error: outboxError);
          final failedMemoUid = switch (type) {
            'create_memo' => payload['uid'] as String?,
            'upload_attachment' => payload['memo_uid'] as String?,
            'delete_attachment' => payload['memo_uid'] as String?,
            _ => null,
          };
          if (failedMemoUid != null && failedMemoUid.isNotEmpty) {
            final memoErrorMessage = memoError.message?.trim();
            final syncError = SyncError(
              code: SyncErrorCode.unknown,
              retryable: false,
              message: memoErrorMessage != null && memoErrorMessage.isNotEmpty
                  ? memoErrorMessage
                  : memoError.toString(),
              presentationKey: 'legacy.msg_sync_failed',
              presentationParams: {'type': type},
              cause: memoError,
            );
            await db.updateMemoSyncState(
              failedMemoUid,
              syncState: 2,
              lastError: encodeSyncError(syncError),
            );
          }
          blockedReason = 'error';
        }
        if (type == 'delete_memo' && memoUid != null && memoUid.isNotEmpty) {
          final currentState = await db.getMemoDeleteTombstoneState(memoUid);
          await db.upsertMemoDeleteTombstone(
            memoUid: memoUid,
            state:
                currentState ??
                AppDatabase.memoDeleteTombstoneStatePendingRemoteDelete,
            lastError: outboxError,
          );
        }
        LogManager.instance.warn(
          'RemoteSync outbox: task_failed',
          error: e,
          context: <String, Object?>{
            'id': id,
            'type': type,
            if (memoUid != null && memoUid.isNotEmpty) 'memoUid': memoUid,
            'transientNetworkError': transientNetworkError,
            'elapsedMs': elapsedMs,
          },
        );
        // Keep ordering: stop processing further ops until this one succeeds.
        blockedType = type;
        shouldStop = true;
      } finally {
        if (!shouldStop && isUploadTask) {
          await syncQueueProgressTracker.markTaskCompleted(outboxId: id);
        }
        syncQueueProgressTracker.clearCurrentTask(outboxId: id);
      }
      _maybeLogOutboxProgress(
        processedCount: processedCount,
        successCount: successCount,
        failedCount: failedCount,
        typeCounts: typeCounts,
        currentType: type,
      );
      syncQueueProgressTracker.updateCompletedTasks(successCount + failedCount);

      if (shouldStop) {
        blockedType = blockedType ?? type;
        break;
      }
    }
    final blockedOnType = blockedType;
    LogManager.instance.info(
      'RemoteSync outbox: summary',
      context: <String, Object?>{
        'processed': processedCount,
        'succeeded': successCount,
        'failed': failedCount,
        'blocked': true,
        'blockedOnType': blockedOnType,
        if (blockedReason != null) 'blockedReason': blockedReason,
        if (typeCounts.isNotEmpty) 'typeCounts': typeCounts,
      },
    );
    return true;
  }

  Future<List<String>> _listCreateMemoAttachmentNames(String memoUid) async {
    final row = await db.getMemoByUid(memoUid);
    final raw = row?['attachments_json'];
    if (raw is! String || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final names = <String>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = item.cast<String, dynamic>();
        final name = (map['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        final externalLink = (map['externalLink'] as String? ?? '').trim();
        if (_isAttachmentReadyForCreateMemo(
          name: name,
          externalLink: externalLink,
        )) {
          names.add(name);
        }
      }
      return names.toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  bool _isAttachmentReadyForCreateMemo({
    required String name,
    required String externalLink,
  }) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return false;
    final normalizedExternalLink = externalLink.trim().toLowerCase();
    if (normalizedName.startsWith('resources/')) {
      return true;
    }
    if (!normalizedName.startsWith('attachments/')) {
      return false;
    }
    if (normalizedExternalLink.isEmpty) return false;
    if (normalizedExternalLink.startsWith('file:')) return false;
    if (normalizedExternalLink.startsWith('content:')) return false;
    return true;
  }

  Future<String?> _handleCreateMemo(Map<String, dynamic> payload) async {
    final uid = payload['uid'] as String?;
    final rawContent = payload['content'] as String?;
    final visibility = payload['visibility'] as String? ?? 'PRIVATE';
    final pinned = payload['pinned'] as bool? ?? false;
    final location = _parseLocationPayload(payload['location']);
    final createTime = _parsePayloadTime(
      payload['create_time'] ??
          payload['createTime'] ??
          payload['display_time'] ??
          payload['displayTime'],
    );
    final displayTime = _parsePayloadTime(
      payload['display_time'] ?? payload['displayTime'],
    );
    final resolvedDisplayTime = displayTime ?? createTime;
    final relationsRaw = payload['relations'];
    final relations = <Map<String, dynamic>>[];
    if (relationsRaw is List) {
      for (final item in relationsRaw) {
        if (item is Map) {
          relations.add(item.cast<String, dynamic>());
        }
      }
    }
    if (uid == null || uid.isEmpty || rawContent == null) {
      throw const FormatException('create_memo missing fields');
    }
    final content = await _rewriteThirdPartyShareInlineUrlsForRemote(
      memoUid: uid,
      content: rawContent,
    );
    final normalizedRelations = normalizeReferenceRelationPayloads(
      memoUid: uid,
      relations: relations,
    );
    final attachmentNames = await _listCreateMemoAttachmentNames(uid);
    final followUpDisplayTime = resolveCreateMemoFollowUpDisplayTime(
      supportsCreateMemoTimestampsInCreateBody:
          api.supportsCreateMemoTimestampsInCreateBody,
      createTime: createTime,
      displayTime: resolvedDisplayTime,
    );
    final followUpCreateTime = resolveCreateMemoFollowUpCreateTime(
      supportsCreateMemoTimestampsInCreateBody:
          api.supportsCreateMemoTimestampsInCreateBody,
      supportsMemoCreateTimeUpdate: api.supportsMemoCreateTimeUpdate,
      createTime: createTime,
    );
    try {
      final created = await api.createMemo(
        memoId: uid,
        content: content,
        visibility: visibility,
        pinned: pinned,
        location: location,
        createTime: api.supportsCreateMemoTimestampsInCreateBody
            ? createTime
            : null,
        displayTime: api.supportsCreateMemoTimestampsInCreateBody
            ? resolvedDisplayTime
            : null,
        attachmentNames: attachmentNames,
        relations: normalizedRelations,
      );
      final remoteUid = created.uid;
      final targetUid = remoteUid.isNotEmpty ? remoteUid : uid;
      if (remoteUid.isNotEmpty && remoteUid != uid) {
        await db.renameMemoUid(oldUid: uid, newUid: remoteUid);
        await db.rewriteOutboxMemoUids(oldUid: uid, newUid: remoteUid);
      }
      if (normalizedRelations.isNotEmpty &&
          !api.supportsCreateMemoRelationsInCreateBody) {
        await _applyMemoRelations(targetUid, normalizedRelations);
      } else if (normalizedRelations.isNotEmpty) {
        _notifyRelationsSynced(targetUid, normalizedRelations);
      }
      if (followUpCreateTime != null || followUpDisplayTime != null) {
        try {
          await api.updateMemo(
            memoUid: targetUid,
            createTime: followUpCreateTime,
            displayTime: followUpDisplayTime,
          );
        } on DioException catch (e) {
          final status = e.response?.statusCode ?? 0;
          if (status != 400 && status != 404 && status != 405) {
            rethrow;
          }
        }
      }
      return targetUid;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 409) {
        if (api.supportsMemoCreateTimeUpdate &&
            (createTime != null || resolvedDisplayTime != null)) {
          await api.updateMemo(
            memoUid: uid,
            createTime: createTime,
            displayTime: resolvedDisplayTime,
          );
        } else if (followUpDisplayTime != null) {
          try {
            await api.updateMemo(
              memoUid: uid,
              displayTime: followUpDisplayTime,
            );
          } on DioException catch (e) {
            final retryStatus = e.response?.statusCode ?? 0;
            if (retryStatus != 400 &&
                retryStatus != 404 &&
                retryStatus != 405) {
              rethrow;
            }
          }
        }
        if (attachmentNames.isNotEmpty) {
          await api.setMemoAttachments(
            memoUid: uid,
            attachmentNames: attachmentNames,
          );
        }
        if (normalizedRelations.isNotEmpty) {
          await _applyMemoRelations(uid, normalizedRelations);
        }
        return uid;
      }
      rethrow;
    }
  }

  DateTime? _parsePayloadTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc();
    if (raw is int) return _epochToDateTime(raw);
    if (raw is double) return _epochToDateTime(raw.round());
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final asInt = int.tryParse(trimmed);
      if (asInt != null) return _epochToDateTime(asInt);
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) return parsed.isUtc ? parsed : parsed.toUtc();
    }
    return null;
  }

  MemoLocation? _parseLocationPayload(dynamic raw) {
    if (raw is Map) {
      return MemoLocation.fromJson(raw.cast<String, dynamic>());
    }
    return null;
  }

  DateTime _epochToDateTime(int value) {
    final ms = value > 1000000000000 ? value : value * 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> _handleUpdateMemo(Map<String, dynamic> payload) async {
    final uid = payload['uid'] as String?;
    if (uid == null || uid.isEmpty) {
      throw const FormatException('update_memo missing uid');
    }
    final rawContent = payload['content'] as String?;
    final content = rawContent == null
        ? null
        : await _rewriteThirdPartyShareInlineUrlsForRemote(
            memoUid: uid,
            content: rawContent,
          );
    final visibility = payload['visibility'] as String?;
    final pinned = payload['pinned'] as bool?;
    final state = payload['state'] as String?;
    final hasLocation = payload.containsKey('location');
    final location = _parseLocationPayload(payload['location']);
    final syncAttachments = payload['sync_attachments'] as bool? ?? false;
    final hasPendingAttachments =
        payload['has_pending_attachments'] as bool? ?? false;
    final hasRelations = payload.containsKey('relations');
    final relationsRaw = payload['relations'];
    final relations = <Map<String, dynamic>>[];
    if (relationsRaw is List) {
      for (final item in relationsRaw) {
        if (item is Map) {
          relations.add(item.cast<String, dynamic>());
        }
      }
    }
    if (hasLocation) {
      await api.updateMemo(
        memoUid: uid,
        content: content,
        visibility: visibility,
        pinned: pinned,
        state: state,
        location: payload['location'] == null ? null : location,
      );
    } else {
      await api.updateMemo(
        memoUid: uid,
        content: content,
        visibility: visibility,
        pinned: pinned,
        state: state,
      );
    }
    if (hasRelations) {
      await _applyMemoRelations(uid, relations);
    }
    if (syncAttachments && !hasPendingAttachments) {
      await _syncMemoAttachments(uid);
    }
  }

  Future<String> _rewriteThirdPartyShareInlineUrlsForRemote({
    required String memoUid,
    required String content,
  }) async {
    if (content.trim().isEmpty) return content;
    final settings = await imageBedRepository.read();
    if (settings.enabled) return content;
    final mappings = await db.listMemoInlineImageSources(memoUid);
    if (mappings.isEmpty) return content;

    var normalized = content;
    for (final entry in mappings.entries) {
      normalized = replaceShareInlineLocalUrlWithRemote(
        normalized,
        localUrl: entry.key,
        remoteUrl: entry.value,
      );
    }
    return normalized;
  }

  Future<void> _applyMemoRelations(
    String memoUid,
    List<Map<String, dynamic>> relations,
  ) async {
    final normalizedUid = _normalizeMemoUid(memoUid);
    if (normalizedUid.isEmpty) return;
    final patch = prepareReferenceRelationPatch(
      memoUid: normalizedUid,
      relations: relations,
    );
    if (!patch.shouldSync) {
      return;
    }

    await api.setMemoRelations(
      memoUid: normalizedUid,
      relations: patch.relations,
    );
    _notifyRelationsSynced(normalizedUid, patch.relations);
  }

  void _notifyRelationsSynced(
    String memoUid,
    List<Map<String, dynamic>> relations,
  ) {
    final uids = _collectRelationUids(memoUid: memoUid, relations: relations);
    if (uids.isEmpty) return;
    onRelationsSynced?.call(uids);
  }

  Set<String> _collectRelationUids({
    required String memoUid,
    required List<Map<String, dynamic>> relations,
  }) {
    final uids = <String>{};
    final normalized = _normalizeMemoUid(memoUid);
    if (normalized.isNotEmpty) {
      uids.add(normalized);
    }
    final normalizedRelations = normalizeReferenceRelationPayloads(
      memoUid: normalized,
      relations: relations,
    );
    for (final relation in normalizedRelations) {
      final relatedRaw = relation['relatedMemo'];
      final relatedName = relatedRaw is Map
          ? ((relatedRaw['name'] as String?) ?? '')
          : '';
      final relatedUid = _normalizeMemoUid(relatedName);
      if (relatedUid.isNotEmpty) {
        uids.add(relatedUid);
      }
    }
    return uids;
  }

  String _normalizeMemoUid(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('memos/')) {
      return trimmed.substring('memos/'.length);
    }
    return trimmed;
  }

  bool _shouldLogOutboxTaskDetail({
    required String type,
    required int processedCount,
  }) {
    if (!_isBulkOutboxTaskType(type)) {
      return true;
    }
    if (processedCount <= RemoteSyncController._bulkOutboxTaskLogHeadCount) {
      return true;
    }
    return processedCount % RemoteSyncController._bulkOutboxTaskLogEvery == 0;
  }

  bool _isBulkOutboxTaskType(String type) {
    return type == 'create_memo' || type == 'update_memo';
  }

  void _maybeLogOutboxProgress({
    required int processedCount,
    required int successCount,
    required int failedCount,
    required Map<String, int> typeCounts,
    required String currentType,
  }) {
    if (processedCount <= 0 ||
        processedCount % RemoteSyncController._outboxProgressLogEvery != 0) {
      return;
    }
    LogManager.instance.info(
      'RemoteSync outbox: progress',
      context: <String, Object?>{
        'processed': processedCount,
        'succeeded': successCount,
        'failed': failedCount,
        'currentType': currentType,
        if (typeCounts.isNotEmpty) 'typeCounts': typeCounts,
      },
    );
  }

  Duration _retryDelayForOutboxAttempt(int attemptsSoFar) {
    if (RemoteSyncController._retryBackoffSteps.isEmpty) {
      return const Duration(seconds: 5);
    }
    final normalizedAttempts = attemptsSoFar < 0 ? 0 : attemptsSoFar;
    final index =
        normalizedAttempts >= RemoteSyncController._retryBackoffSteps.length
        ? RemoteSyncController._retryBackoffSteps.length - 1
        : normalizedAttempts;
    return RemoteSyncController._retryBackoffSteps[index];
  }

  String? _outboxMemoUid(String type, Map<String, dynamic> payload) {
    return switch (type) {
      'create_memo' ||
      'update_memo' ||
      'delete_memo' => payload['uid'] as String?,
      'upload_attachment' ||
      'delete_attachment' => payload['memo_uid'] as String?,
      _ => null,
    };
  }

  Future<void> _handleDeleteMemo(Map<String, dynamic> payload) async {
    final uid = payload['uid'] as String?;
    final force = payload['force'] as bool? ?? false;
    if (uid == null || uid.isEmpty) {
      throw const FormatException('delete_memo missing uid');
    }
    try {
      await api.deleteMemo(memoUid: uid, force: force);
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 404) return;
      rethrow;
    }
  }
}
