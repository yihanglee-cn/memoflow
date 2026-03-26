import 'package:flutter_test/flutter_test.dart';

import 'package:memos_flutter_app/application/desktop/desktop_exit_coordinator.dart';

void main() {
  test('desktop exit closes main window before databases', () {
    final steps = DesktopExitCoordinator.debugExitStepOrder();

    expect(steps, <String>[
      'close_sub_windows',
      'unregister_hotkey',
      'dispose_tray',
      'disable_prevent_close',
      'close_main_window',
      'await_main_window_teardown',
      'close_databases',
    ]);

    expect(
      steps.indexOf('close_main_window'),
      lessThan(steps.indexOf('close_databases')),
    );
  });

  test(
    'desktop exit uses destroy semantics for main-window termination step',
    () {
      expect(
        DesktopExitCoordinator.debugMainWindowTerminationAction(),
        'destroy',
      );
    },
  );
}
