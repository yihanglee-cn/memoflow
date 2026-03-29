import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/memoflow_palette.dart';
import '../../../i18n/strings.g.dart';

class MemoFlowFab extends StatefulWidget {
  const MemoFlowFab({
    super.key,
    required this.onPressed,
    required this.hapticsEnabled,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
  });

  final VoidCallback? onPressed;
  final Future<void> Function(LongPressStartDetails details)? onLongPressStart;
  final void Function(LongPressMoveUpdateDetails details)?
  onLongPressMoveUpdate;
  final void Function(LongPressEndDetails details)? onLongPressEnd;
  final bool hapticsEnabled;

  @override
  State<MemoFlowFab> createState() => _MemoFlowFabState();
}

class _MemoFlowFabState extends State<MemoFlowFab> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).brightness == Brightness.dark
        ? MemoFlowPalette.backgroundDark
        : MemoFlowPalette.backgroundLight;

    return GestureDetector(
      onTapDown: widget.onPressed == null
          ? null
          : (_) {
              if (widget.hapticsEnabled) {
                HapticFeedback.selectionClick();
              }
              setState(() => _pressed = true);
            },
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: widget.onPressed == null
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            },
      onLongPressStart: widget.onLongPressStart == null
          ? null
          : (details) {
              setState(() => _pressed = false);
              if (widget.hapticsEnabled) {
                HapticFeedback.mediumImpact();
              }
              unawaited(widget.onLongPressStart!.call(details));
            },
      onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
      onLongPressEnd: widget.onLongPressEnd,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 160),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: MemoFlowPalette.primary,
            shape: BoxShape.circle,
            border: Border.all(color: bg, width: 4),
            boxShadow: [
              BoxShadow(
                blurRadius: 24,
                offset: const Offset(0, 10),
                color: MemoFlowPalette.primary.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.2
                      : 0.3,
                ),
              ),
            ],
          ),
          child: const Icon(Icons.add, size: 32, color: Colors.white),
        ),
      ),
    );
  }
}

class BackToTopButton extends StatefulWidget {
  const BackToTopButton({
    super.key,
    required this.visible,
    required this.hapticsEnabled,
    required this.onPressed,
  });

  final bool visible;
  final bool hapticsEnabled;
  final VoidCallback onPressed;

  @override
  State<BackToTopButton> createState() => _BackToTopButtonState();
}

class _BackToTopButtonState extends State<BackToTopButton> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = MemoFlowPalette.primary;
    final iconColor = Colors.white;
    final scale = widget.visible ? (_pressed ? 0.92 : 1.0) : 0.85;

    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Semantics(
            button: true,
            label: context.t.strings.legacy.msg_back_top,
            child: GestureDetector(
              onTapDown: (_) {
                if (widget.hapticsEnabled) {
                  HapticFeedback.selectionClick();
                }
                setState(() => _pressed = true);
              },
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) {
                setState(() => _pressed = false);
                widget.onPressed();
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                      color: MemoFlowPalette.primary.withValues(
                        alpha: isDark ? 0.35 : 0.25,
                      ),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.keyboard_arrow_up,
                  size: 26,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
