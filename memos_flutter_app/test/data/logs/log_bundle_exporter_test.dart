import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/data/logs/log_bundle_exporter.dart';

void main() {
  group('extractAiExportLogLines', () {
    test('keeps ai settings and adapter lines only', () {
      final lines = <String>[
        '[2026-03-11T11:00:00.000Z] INFO App: AI settings loaded | ctx={}',
        '[2026-03-11T11:00:01.000Z] INFO App: Sync started | ctx={}',
        '[2026-03-11T11:00:02.000Z] WARN App: AI adapter request failed | ctx={}',
        '[2026-03-11T11:00:03.000Z] INFO App: AI settings model sync finished | ctx={}',
      ];

      expect(
        extractAiExportLogLines(lines),
        equals(<String>[
          '[2026-03-11T11:00:00.000Z] INFO App: AI settings loaded | ctx={}',
          '[2026-03-11T11:00:02.000Z] WARN App: AI adapter request failed | ctx={}',
          '[2026-03-11T11:00:03.000Z] INFO App: AI settings model sync finished | ctx={}',
        ]),
      );
    });
  });
}
