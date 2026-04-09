import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/features/import/import_flow_screens.dart';

import '../settings/settings_test_harness.dart';

void main() {
  testWidgets('shows SwashbucklerDiary import source and triggers callback', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      buildSettingsTestApp(
        home: ImportSourceScreen(
          onSelectSwashbucklerDiary: () {
            tapped = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SwashbucklerDiary'), findsOneWidget);
    expect(find.text('JSON / Markdown / TXT ZIP'), findsOneWidget);

    await tester.tap(find.text('SwashbucklerDiary'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
