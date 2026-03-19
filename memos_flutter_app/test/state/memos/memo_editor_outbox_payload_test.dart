import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memos_flutter_app/data/db/app_database.dart';
import 'package:memos_flutter_app/state/memos/memo_editor_providers.dart';
import 'package:memos_flutter_app/state/memos/memo_timeline_provider.dart';
import 'package:memos_flutter_app/state/system/database_provider.dart';

import '../../test_support.dart';

void main() {
  late TestSupport support;

  setUpAll(() async {
    support = await initializeTestSupport();
  });

  tearDownAll(() async {
    await support.dispose();
  });

  test(
    'MemoEditorController enqueues upload_attachment with skip_compression',
    () async {
      final dbName = uniqueDbName('memo_editor_skip_compression');
      final db = AppDatabase(dbName: dbName);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          memoTimelineServiceProvider.overrideWithValue(
            MemoTimelineService(
              db: db,
              account: null,
              triggerSync: () async {},
            ),
          ),
        ],
      );
      final controller = container.read(memoEditorControllerProvider);
      final now = DateTime.utc(2026, 3, 13, 18, 0);

      addTearDown(() async {
        container.dispose();
        await db.close();
        await deleteTestDatabase(dbName);
      });

      await controller.saveMemo(
        existing: null,
        uid: 'memo-1',
        content: 'offline memo',
        visibility: 'PRIVATE',
        pinned: false,
        state: 'NORMAL',
        createTime: now,
        now: now,
        tags: const <String>[],
        attachments: const <Map<String, dynamic>>[],
        location: null,
        locationChanged: false,
        relationCount: 0,
        hasPrimaryChanges: false,
        attachmentsToDelete: const [],
        includeRelations: false,
        relations: const <Map<String, dynamic>>[],
        shouldSyncAttachments: false,
        hasPendingAttachments: true,
        pendingAttachments: const [
          MemoEditorPendingAttachment(
            uid: 'att-1',
            filePath: '/tmp/sample.png',
            filename: 'sample.png',
            mimeType: 'image/png',
            size: 42,
            skipCompression: true,
          ),
        ],
      );

      final outbox = await db.listOutboxPendingByType('upload_attachment');
      expect(outbox, hasLength(1));

      final payload =
          jsonDecode(outbox.single['payload'] as String)
              as Map<String, dynamic>;
      expect(payload['uid'], 'att-1');
      expect(payload['memo_uid'], 'memo-1');
      expect(payload['skip_compression'], isTrue);
    },
  );
}
