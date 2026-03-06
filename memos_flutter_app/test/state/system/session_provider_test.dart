import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memos_flutter_app/core/desktop_runtime_role.dart';
import 'package:memos_flutter_app/core/storage_read.dart';
import 'package:memos_flutter_app/data/repositories/accounts_repository.dart';
import 'package:memos_flutter_app/data/repositories/windows_locked_secure_storage.dart';
import 'package:memos_flutter_app/state/system/session_provider.dart';

class _FakeAccountsRepository extends AccountsRepository {
  _FakeAccountsRepository({
    required AccountsState initialState,
    this.failingWrites = 0,
  }) : _persisted = initialState,
       super(const FlutterSecureStorage());

  AccountsState _persisted;
  int failingWrites;
  int writeAttempts = 0;

  AccountsState get persisted => _persisted;

  @override
  Future<StorageReadResult<AccountsState>> readWithStatus() async {
    return StorageReadResult.success(_persisted);
  }

  @override
  Future<AccountsState> read() async => _persisted;

  @override
  Future<void> write(AccountsState state) async {
    writeAttempts += 1;
    if (failingWrites > 0) {
      failingWrites -= 1;
      throw StateError('simulated write failure');
    }
    _persisted = state;
  }
}

Future<void> _settleProviderLoads() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'switchWorkspace retries persisting current workspace after a failed write',
    () async {
      final repository = _FakeAccountsRepository(
        initialState: const AccountsState(accounts: [], currentKey: null),
        failingWrites: 1,
      );
      final container = ProviderContainer(
        overrides: [
          accountsRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      addTearDown(container.dispose);

      container.read(appSessionProvider);
      await _settleProviderLoads();

      final controller = container.read(appSessionProvider.notifier);

      await controller.switchWorkspace('local-workspace');
      expect(
        container.read(appSessionProvider).valueOrNull?.currentKey,
        'local-workspace',
      );
      expect(repository.writeAttempts, 1);
      expect(repository.persisted.currentKey, isNull);

      await controller.switchWorkspace('local-workspace');
      expect(repository.writeAttempts, 2);
      expect(repository.persisted.currentKey, 'local-workspace');
    },
  );

  test('secureStorageProvider defaults to main-app Windows role', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final storage = container.read(secureStorageProvider);

    expect(storage, isA<WindowsLockedQueuedFlutterSecureStorage>());
    expect(
      (storage as WindowsLockedQueuedFlutterSecureStorage).runtimeRole,
      DesktopRuntimeRole.mainApp,
    );
  });

  for (final role in DesktopRuntimeRole.values) {
    test('secureStorageProvider keeps Windows lock wrapper for ${role.name}', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final container = ProviderContainer(
        overrides: [
          desktopRuntimeRoleProvider.overrideWith((ref) => role),
        ],
      );
      addTearDown(container.dispose);

      final storage = container.read(secureStorageProvider);

      expect(storage, isA<WindowsLockedQueuedFlutterSecureStorage>());
      expect(
        (storage as WindowsLockedQueuedFlutterSecureStorage).runtimeRole,
        role,
      );
    });
  }
}
