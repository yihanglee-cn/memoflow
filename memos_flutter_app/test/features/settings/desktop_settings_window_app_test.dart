import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memos_flutter_app/core/storage_read.dart';
import 'package:memos_flutter_app/data/models/account.dart';
import 'package:memos_flutter_app/data/models/instance_profile.dart';
import 'package:memos_flutter_app/features/settings/desktop_settings_window_app.dart';
import 'package:memos_flutter_app/state/settings/preferences_provider.dart';
import 'package:memos_flutter_app/state/system/session_provider.dart';

const MethodChannel _windowManagerChannel = MethodChannel('window_manager');
const MethodChannel _multiWindowChannel = MethodChannel(
  'mixin.one/flutter_multi_window',
);
const MethodChannel _multiWindowEventChannel = MethodChannel(
  'mixin.one/flutter_multi_window_channel',
);

class _TestSessionController extends AppSessionController {
  _TestSessionController()
    : super(
        const AsyncValue.data(AppSessionState(accounts: [], currentKey: null)),
      );

  int reloadCalls = 0;

  @override
  Future<void> addAccountWithPat({
    required Uri baseUrl,
    required String personalAccessToken,
    bool? useLegacyApiOverride,
    String? serverVersionOverride,
  }) async {}

  @override
  Future<void> addAccountWithPassword({
    required Uri baseUrl,
    required String username,
    required String password,
    required bool useLegacyApi,
    String? serverVersionOverride,
  }) async {}

  @override
  Future<void> removeAccount(String accountKey) async {}

  @override
  Future<void> switchAccount(String accountKey) async {}

  @override
  Future<void> setCurrentKey(String? key) async {}

  @override
  Future<void> switchWorkspace(String workspaceKey) async {}

  @override
  Future<void> refreshCurrentUser({bool ignoreErrors = true}) async {}

  @override
  Future<void> reloadFromStorage() async {
    reloadCalls += 1;
  }

  @override
  bool resolveUseLegacyApiForAccount({
    required Account account,
    required bool globalDefault,
  }) => globalDefault;

  @override
  InstanceProfile resolveEffectiveInstanceProfileForAccount({
    required Account account,
  }) => account.instanceProfile;

  @override
  String resolveEffectiveServerVersionForAccount({required Account account}) =>
      account.serverVersionOverride ?? account.instanceProfile.version;

  @override
  Future<void> setCurrentAccountUseLegacyApiOverride(bool value) async {}

  @override
  Future<void> setCurrentAccountServerVersionOverride(String? version) async {}

  @override
  Future<InstanceProfile> detectCurrentAccountInstanceProfile() async {
    return const InstanceProfile.empty();
  }
}

class _TestAppPreferencesRepository extends AppPreferencesRepository {
  _TestAppPreferencesRepository()
    : super(const FlutterSecureStorage(), accountKey: null);

  @override
  Future<StorageReadResult<AppPreferences>> readWithStatus() async {
    return StorageReadResult.success(
      AppPreferences.defaultsForLanguage(AppLanguage.en),
    );
  }

  @override
  Future<AppPreferences> read() async {
    return AppPreferences.defaultsForLanguage(AppLanguage.en);
  }

  @override
  Future<void> write(AppPreferences prefs) async {}

  @override
  Future<void> clear() async {}
}

class _TestAppPreferencesController extends AppPreferencesController {
  _TestAppPreferencesController(Ref ref)
    : super(
        ref,
        _TestAppPreferencesRepository(),
        onLoaded: () {
          ref.read(appPreferencesLoadedProvider.notifier).state = true;
        },
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, (call) async {
          switch (call.method) {
            case 'ensureInitialized':
            case 'setAsFrameless':
            case 'setHasShadow':
            case 'setBackgroundColor':
            case 'focus':
            case 'restore':
            case 'show':
            case 'hide':
            case 'close':
              return null;
            case 'isVisible':
              return true;
            case 'isMinimized':
              return false;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_multiWindowChannel, (call) async {
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_multiWindowEventChannel, (call) async {
          if (call.method == 'desktop.quickInput.ping') {
            throw PlatformException(
              code: 'boom',
              message: 'main window unavailable',
            );
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_multiWindowChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_multiWindowEventChannel, null);
  });

  testWidgets(
    'shows retryable main-window error state without reloading local session',
    (tester) async {
      final sessionController = _TestSessionController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSessionProvider.overrideWith((ref) => sessionController),
            appPreferencesProvider.overrideWith(
              (ref) => _TestAppPreferencesController(ref),
            ),
          ],
          child: const DesktopSettingsWindowApp(windowId: 7),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.text(
          'Main window unavailable. Please reopen settings from the main window.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(sessionController.reloadCalls, 0);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(sessionController.reloadCalls, 0);
      expect(
        find.text(
          'Main window unavailable. Please reopen settings from the main window.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

