import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/core/desktop/shortcuts.dart';

void main() {
  test('windows global actions include paging shortcuts', () {
    final actions = desktopShortcutGlobalActionsForPlatform(
      TargetPlatform.windows,
    );

    expect(actions, contains(DesktopShortcutAction.previousPage));
    expect(actions, contains(DesktopShortcutAction.nextPage));
  });

  test('non-windows global actions exclude paging shortcuts', () {
    final actions = desktopShortcutGlobalActionsForPlatform(
      TargetPlatform.macOS,
    );

    expect(actions, isNot(contains(DesktopShortcutAction.previousPage)));
    expect(actions, isNot(contains(DesktopShortcutAction.nextPage)));
  });

  test('paging shortcuts default to plain PageUp and PageDown', () {
    expect(
      desktopShortcutDefaultBindings[DesktopShortcutAction.previousPage],
      DesktopShortcutBinding(
        keyId: LogicalKeyboardKey.pageUp.keyId,
        primary: false,
        shift: false,
        alt: false,
      ),
    );
    expect(
      desktopShortcutDefaultBindings[DesktopShortcutAction.nextPage],
      DesktopShortcutBinding(
        keyId: LogicalKeyboardKey.pageDown.keyId,
        primary: false,
        shift: false,
        alt: false,
      ),
    );
  });

  test('plain binding allowance is limited to paging actions', () {
    expect(
      desktopShortcutActionAllowsPlainBinding(
        DesktopShortcutAction.previousPage,
        LogicalKeyboardKey.pageUp,
      ),
      isTrue,
    );
    expect(
      desktopShortcutActionAllowsPlainBinding(
        DesktopShortcutAction.nextPage,
        LogicalKeyboardKey.pageDown,
      ),
      isTrue,
    );
    expect(
      desktopShortcutActionAllowsPlainBinding(
        DesktopShortcutAction.search,
        LogicalKeyboardKey.pageUp,
      ),
      isFalse,
    );
  });

  test('paging binding labels keep PageUp and PageDown names', () {
    expect(
      desktopShortcutBindingLabel(
        DesktopShortcutBinding(
          keyId: LogicalKeyboardKey.pageUp.keyId,
          primary: false,
          shift: false,
          alt: false,
        ),
      ),
      'PageUp',
    );
    expect(
      desktopShortcutBindingLabel(
        DesktopShortcutBinding(
          keyId: LogicalKeyboardKey.pageDown.keyId,
          primary: false,
          shift: false,
          alt: false,
        ),
      ),
      'PageDown',
    );
  });

  test('guide binding label uses the active search shortcut', () {
    expect(
      desktopShortcutGuideBindingLabel(
        desktopShortcutDefaultBindings,
        DesktopShortcutAction.search,
      ),
      'Ctrl + K',
    );
  });

  test('guide binding label keeps F1 fallback for shortcut overview', () {
    expect(
      desktopShortcutGuideBindingLabel(
        desktopShortcutDefaultBindings,
        DesktopShortcutAction.shortcutOverview,
      ),
      'Shift + / / F1',
    );
  });
}
