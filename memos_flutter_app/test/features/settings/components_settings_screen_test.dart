import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/features/settings/components_settings_screen.dart';
import 'package:memos_flutter_app/i18n/strings.g.dart';

void main() {
  Widget buildTestApp() {
    LocaleSettings.setLocale(AppLocale.en);
    return TranslationProvider(
      child: MaterialApp(
        locale: AppLocale.en.flutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(body: ThirdPartyShareCopyrightDialog()),
      ),
    );
  }

  testWidgets(
    'requires five-second wait before acknowledging third-party share notice',
    (tester) async {
      await tester.pumpWidget(buildTestApp());

      final checkboxTileFinder = find.byType(CheckboxListTile);
      final enableButtonFinder = find.widgetWithText(FilledButton, 'Enable');

      var checkboxTile = tester.widget<CheckboxListTile>(checkboxTileFinder);
      var enableButton = tester.widget<FilledButton>(enableButtonFinder);

      expect(
        find.text('I understand (5s before it can be checked)'),
        findsOneWidget,
      );
      expect(checkboxTile.onChanged, isNull);
      expect(enableButton.onPressed, isNull);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      checkboxTile = tester.widget<CheckboxListTile>(checkboxTileFinder);
      expect(find.text('I understand'), findsOneWidget);
      expect(checkboxTile.onChanged, isNotNull);

      await tester.ensureVisible(checkboxTileFinder);
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();

      enableButton = tester.widget<FilledButton>(enableButtonFinder);
      expect(enableButton.onPressed, isNotNull);
    },
  );
}
