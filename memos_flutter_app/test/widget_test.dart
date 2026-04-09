// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:memos_flutter_app/app.dart';
import 'package:memos_flutter_app/core/storage_read.dart';
import 'package:memos_flutter_app/data/models/account.dart';
import 'package:memos_flutter_app/data/models/app_preferences.dart';
import 'package:memos_flutter_app/data/models/device_preferences.dart';
import 'package:memos_flutter_app/data/models/instance_profile.dart';
import 'package:memos_flutter_app/data/models/workspace_preferences.dart';
import 'package:memos_flutter_app/features/onboarding/language_selection_screen.dart';
import 'package:memos_flutter_app/state/settings/device_preferences_provider.dart';
import 'package:memos_flutter_app/state/settings/preferences_migration_service.dart';
import 'package:memos_flutter_app/state/settings/workspace_preferences_provider.dart';
import 'package:memos_flutter_app/state/system/local_library_provider.dart';
import 'package:memos_flutter_app/state/system/session_provider.dart';

void main() {
  testWidgets('shows onboarding when no workspace is available', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSessionProvider.overrideWith((ref) => _TestSessionController()),
          devicePreferencesProvider.overrideWith(
            (ref) => _TestDevicePreferencesController(
              ref,
              DevicePreferences.defaultsForLanguage(
                AppLanguage.en,
              ).copyWith(onboardingMode: null),
            ),
          ),
          currentWorkspacePreferencesProvider.overrideWith(
            (ref) => _TestWorkspacePreferencesController(
              ref,
              WorkspacePreferences.defaults,
            ),
          ),
          currentLocalLibraryProvider.overrideWith((ref) => null),
        ],
        child: const App(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    final onboardingEntry = find.byType(
      LanguageSelectionScreen,
      skipOffstage: false,
    );
    expect(onboardingEntry, findsAtLeastNWidgets(1));
  });
}

class _TestSessionController extends AppSessionController {
  _TestSessionController()
    : super(
        const AsyncValue.data(AppSessionState(accounts: [], currentKey: null)),
      );

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
  Future<void> reloadFromStorage() async {}

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

class _TestDevicePreferencesRepository extends DevicePreferencesRepository {
  _TestDevicePreferencesRepository(this._stored)
    : super(PreferencesMigrationService(const FlutterSecureStorage()));

  DevicePreferences _stored;

  @override
  Future<StorageReadResult<DevicePreferences>> readWithStatus() async {
    return StorageReadResult.success(_stored);
  }

  @override
  Future<DevicePreferences> read() async {
    return _stored;
  }

  @override
  Future<void> write(DevicePreferences prefs) async {
    _stored = prefs;
  }
}

class _TestDevicePreferencesController extends DevicePreferencesController {
  _TestDevicePreferencesController(Ref ref, DevicePreferences initial)
    : super(
        ref,
        _TestDevicePreferencesRepository(initial),
        onLoaded: () {
          ref.read(devicePreferencesLoadedProvider.notifier).state = true;
        },
      ) {
    state = initial;
  }
}

class _TestWorkspacePreferencesRepository
    extends WorkspacePreferencesRepository {
  _TestWorkspacePreferencesRepository(this._stored)
    : super(
        PreferencesMigrationService(const FlutterSecureStorage()),
        workspaceKey: 'test-workspace',
      );

  WorkspacePreferences _stored;

  @override
  Future<StorageReadResult<WorkspacePreferences>> readWithStatus() async {
    return StorageReadResult.success(_stored);
  }

  @override
  Future<WorkspacePreferences> read() async {
    return _stored;
  }

  @override
  Future<void> write(WorkspacePreferences prefs) async {
    _stored = prefs;
  }
}

class _TestWorkspacePreferencesController
    extends WorkspacePreferencesController {
  _TestWorkspacePreferencesController(Ref ref, WorkspacePreferences initial)
    : super(
        ref,
        _TestWorkspacePreferencesRepository(initial),
        onLoaded: () {
          ref.read(workspacePreferencesLoadedProvider.notifier).state = true;
        },
      ) {
    state = initial;
  }
}
