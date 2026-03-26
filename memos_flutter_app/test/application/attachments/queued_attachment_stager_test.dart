import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:memos_flutter_app/application/attachments/queued_attachment_stager.dart';

import '../../test_support.dart';

void main() {
  late TestSupport support;

  setUpAll(() async {
    support = await initializeTestSupport();
  });

  tearDownAll(() async {
    await support.dispose();
  });

  Future<QueuedAttachmentStager> createStager({
    CopyContentUriToLocalFile? copyContentUriToLocalFile,
  }) async {
    final supportDir = await support.createTempDir('queued_stager_support');
    return QueuedAttachmentStager(
      resolveSupportDirectory: () async => supportDir,
      copyContentUriToLocalFile: copyContentUriToLocalFile,
    );
  }

  Future<File> createSourceFile(
    String prefix, {
    String filename = 'sample.png',
  }) async {
    final dir = await support.createTempDir(prefix);
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(const <int>[137, 80, 78, 71, 1, 2, 3, 4]);
    return file;
  }

  test('stageDraftAttachment copies local files into managed root', () async {
    final sourceFile = await createSourceFile('queued_stager_local');
    final stager = await createStager();

    final staged = await stager.stageDraftAttachment(
      uid: 'att-1',
      filePath: sourceFile.path,
      filename: 'sample.png',
      mimeType: 'image/png',
      size: await sourceFile.length(),
      scopeKey: 'memo-1',
    );

    expect(stager.isManagedPath(staged.filePath), isTrue);
    expect(staged.filePath, isNot(sourceFile.path));
    expect(File(staged.filePath).existsSync(), isTrue);
    expect(
      File(staged.filePath).readAsBytesSync(),
      sourceFile.readAsBytesSync(),
    );
  });

  test(
    'stageDraftAttachment copies content uri via injected callback',
    () async {
      final copied = <String, String>{};
      final stager = await createStager(
        copyContentUriToLocalFile: (sourceUri, destinationPath) async {
          copied['source'] = sourceUri;
          copied['destination'] = destinationPath;
          await File(destinationPath).writeAsString('hello');
        },
      );

      final staged = await stager.stageDraftAttachment(
        uid: 'att-1',
        filePath: 'content://media/external/file/1',
        filename: 'sample.txt',
        mimeType: 'text/plain',
        size: 0,
        scopeKey: 'memo-1',
      );

      expect(copied['source'], 'content://media/external/file/1');
      expect(copied['destination'], endsWith('.part'));
      expect(File(staged.filePath).readAsStringSync(), 'hello');
      expect(staged.size, 5);
    },
  );

  test('stageDraftAttachment is idempotent for managed files', () async {
    final sourceFile = await createSourceFile('queued_stager_idempotent');
    final stager = await createStager();

    final first = await stager.stageDraftAttachment(
      uid: 'att-1',
      filePath: sourceFile.path,
      filename: 'sample.png',
      mimeType: 'image/png',
      size: await sourceFile.length(),
      scopeKey: 'memo-1',
    );
    final second = await stager.stageDraftAttachment(
      uid: 'att-1',
      filePath: first.filePath,
      filename: first.filename,
      mimeType: first.mimeType,
      size: first.size,
      scopeKey: 'memo-1',
    );

    expect(second.filePath, first.filePath);
    expect(second.size, first.size);
  });

  test('stageDraftAttachment fails when source file is missing', () async {
    final stager = await createStager();
    final missingPath =
        '${(await support.createTempDir('queued_stager_missing')).path}${Platform.pathSeparator}missing.png';

    await expectLater(
      () => stager.stageDraftAttachment(
        uid: 'att-1',
        filePath: missingPath,
        filename: 'missing.png',
        mimeType: 'image/png',
        size: 0,
        scopeKey: 'memo-1',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('deleteManagedFile only deletes files under managed root', () async {
    final sourceFile = await createSourceFile('queued_stager_delete');
    final externalFile = await createSourceFile(
      'queued_stager_external',
      filename: 'external.txt',
    );
    final stager = await createStager();

    final staged = await stager.stageDraftAttachment(
      uid: 'att-1',
      filePath: sourceFile.path,
      filename: 'sample.png',
      mimeType: 'image/png',
      size: await sourceFile.length(),
      scopeKey: 'memo-1',
    );

    await stager.deleteManagedFile(externalFile.path);
    expect(externalFile.existsSync(), isTrue);

    await stager.deleteManagedFile(staged.filePath);
    expect(File(staged.filePath).existsSync(), isFalse);
  });
}
