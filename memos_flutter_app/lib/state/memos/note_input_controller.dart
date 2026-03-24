import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tags.dart';
import '../../data/models/attachment.dart';
import '../../data/models/local_memo.dart';
import '../../data/models/memo_location.dart';
import '../../features/share/share_inline_image_content.dart';
import 'create_memo_outbox_payload.dart';
import '../system/database_provider.dart';

class NoteInputPendingAttachment {
  const NoteInputPendingAttachment({
    required this.uid,
    required this.filePath,
    required this.filename,
    required this.mimeType,
    required this.size,
    this.skipCompression = false,
    this.shareInlineImage = false,
    this.fromThirdPartyShare = false,
    this.sourceUrl,
  });

  final String uid;
  final String filePath;
  final String filename;
  final String mimeType;
  final int size;
  final bool skipCompression;
  final bool shareInlineImage;
  final bool fromThirdPartyShare;
  final String? sourceUrl;
}

class NoteInputController {
  NoteInputController(this._ref);

  final Ref _ref;

  Future<void> createMemo({
    required String uid,
    required String content,
    String? syncContent,
    required String visibility,
    required DateTime now,
    required List<String> tags,
    required List<Map<String, dynamic>> attachments,
    required MemoLocation? location,
    required bool hasAttachments,
    required List<Map<String, dynamic>> relations,
    required List<NoteInputPendingAttachment> pendingAttachments,
  }) async {
    final db = _ref.read(databaseProvider);

    await db.upsertMemo(
      uid: uid,
      content: content,
      visibility: visibility,
      pinned: false,
      state: 'NORMAL',
      createTimeSec: now.toUtc().millisecondsSinceEpoch ~/ 1000,
      updateTimeSec: now.toUtc().millisecondsSinceEpoch ~/ 1000,
      tags: tags,
      attachments: attachments,
      location: location,
      relationCount: 0,
      syncState: 1,
    );

    for (final attachment in pendingAttachments) {
      final sourceUrl = attachment.sourceUrl?.trim();
      if (attachment.shareInlineImage &&
          attachment.fromThirdPartyShare &&
          sourceUrl != null &&
          sourceUrl.isNotEmpty) {
        await db.upsertMemoInlineImageSource(
          memoUid: uid,
          localUrl: Uri.file(attachment.filePath).toString(),
          sourceUrl: sourceUrl,
        );
      }
    }

    await db.enqueueOutbox(
      type: 'create_memo',
      payload: buildCreateMemoOutboxPayload(
        uid: uid,
        content: syncContent ?? content,
        visibility: visibility,
        pinned: false,
        createTimeSec: now.toUtc().millisecondsSinceEpoch ~/ 1000,
        hasAttachments: hasAttachments,
        location: location,
        relations: relations,
      ),
    );

    for (final attachment in pendingAttachments) {
      await db.enqueueOutbox(
        type: 'upload_attachment',
        payload: {
          'uid': attachment.uid,
          'memo_uid': uid,
          'file_path': attachment.filePath,
          'filename': attachment.filename,
          'mime_type': attachment.mimeType,
          'file_size': attachment.size,
          'skip_compression': attachment.skipCompression,
          'share_inline_image': attachment.shareInlineImage,
          'from_third_party_share': attachment.fromThirdPartyShare,
          if (attachment.shareInlineImage)
            'share_inline_local_url': Uri.file(attachment.filePath).toString(),
        },
      );
    }
  }

  Future<void> appendDeferredThirdPartyShareInlineImage({
    required String memoUid,
    required String sourceUrl,
    required NoteInputPendingAttachment attachment,
  }) async {
    final db = _ref.read(databaseProvider);
    final row = await db.getMemoByUid(memoUid);
    if (row == null) {
      throw StateError('Memo not found: $memoUid');
    }

    final memo = LocalMemo.fromDb(row);
    final localUrl = Uri.file(attachment.filePath).toString();
    final normalizedSourceUrl =
        attachment.sourceUrl?.trim() ?? sourceUrl.trim();
    final updatedContent = replaceShareInlineImageUrl(
      memo.content,
      fromUrl: sourceUrl,
      toUrl: localUrl,
    );
    if (updatedContent == memo.content) {
      return;
    }

    final updatedAttachments = <Map<String, dynamic>>[
      ...memo.attachments.map((item) => item.toJson()),
      Attachment(
        name: 'attachments/${attachment.uid}',
        filename: attachment.filename,
        type: attachment.mimeType,
        size: attachment.size,
        externalLink: localUrl,
      ).toJson(),
    ];
    final now = DateTime.now().toUtc();

    await db.upsertMemo(
      uid: memo.uid,
      content: updatedContent,
      visibility: memo.visibility,
      pinned: memo.pinned,
      state: memo.state,
      createTimeSec: memo.createTime.toUtc().millisecondsSinceEpoch ~/ 1000,
      updateTimeSec: now.millisecondsSinceEpoch ~/ 1000,
      tags: extractTags(updatedContent),
      attachments: updatedAttachments,
      location: memo.location,
      relationCount: memo.relationCount,
      syncState: 1,
      lastError: null,
    );

    if (normalizedSourceUrl.isNotEmpty) {
      await db.upsertMemoInlineImageSource(
        memoUid: memo.uid,
        localUrl: localUrl,
        sourceUrl: normalizedSourceUrl,
      );
    }

    await db.enqueueOutbox(
      type: 'update_memo',
      payload: {
        'uid': memo.uid,
        'content': updatedContent,
        'visibility': memo.visibility,
        'pinned': memo.pinned,
      },
    );
    await db.enqueueOutbox(
      type: 'upload_attachment',
      payload: {
        'uid': attachment.uid,
        'memo_uid': memo.uid,
        'file_path': attachment.filePath,
        'filename': attachment.filename,
        'mime_type': attachment.mimeType,
        'file_size': attachment.size,
        'skip_compression': attachment.skipCompression,
        'share_inline_image': true,
        'from_third_party_share': true,
        'share_inline_local_url': localUrl,
      },
    );
  }
}
