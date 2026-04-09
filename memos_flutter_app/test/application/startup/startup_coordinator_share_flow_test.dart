import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/data/models/app_preferences.dart';

import 'startup_coordinator_test_harness.dart';

void main() {
  group('StartupCoordinator share flow', () {
    testWidgets('clears startup share state when third-party share is disabled', (
      tester,
    ) async {
      final bootstrapAdapter = FakeBootstrapAdapter(
        preferences: AppPreferences.defaults.copyWith(
          thirdPartyShareEnabled: false,
        ),
        preferencesLoaded: true,
        session: buildTestSessionWithAccount(),
      );
      final harness = await pumpStartupCoordinatorHarness(
        tester,
        bootstrapAdapter: bootstrapAdapter,
      );

      await harness.coordinator.handleShareLaunch(buildPreviewSharePayload());
      await tester.pump();
      await tester.pump();

      expect(harness.coordinator.startupSharePreviewPayload, isNull);
      expect(harness.coordinator.shouldDeferHeavyStartupWork, isFalse);
      expect(harness.syncOrchestrator.maybeSyncOnLaunchCount, 1);
    });

    testWidgets('preview flow flushes deferred launch sync after route closes', (
      tester,
    ) async {
      final bootstrapAdapter = FakeBootstrapAdapter(
        preferencesLoaded: true,
        session: buildTestSessionWithAccount(),
      );
      final harness = await pumpStartupCoordinatorHarness(
        tester,
        bootstrapAdapter: bootstrapAdapter,
        sharePreviewRouteBuilder: (_) => buildAutoPopPreviewRoute(),
      );

      await harness.coordinator.handleShareLaunch(buildPreviewSharePayload());
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(harness.coordinator.startupSharePreviewPayload, isNull);
      expect(harness.coordinator.shouldDeferHeavyStartupWork, isFalse);
      expect(harness.syncOrchestrator.maybeSyncOnLaunchCount, 1);
      expect(
        harness.syncOrchestrator.lastLaunchPrefs,
        bootstrapAdapter.workspacePreferences,
      );
    });
  });
}
