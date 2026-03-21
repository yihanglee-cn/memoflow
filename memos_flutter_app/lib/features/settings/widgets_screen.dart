import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_localization.dart';
import '../../core/memoflow_palette.dart';
import '../../core/top_toast.dart';
import '../../application/widgets/home_widget_service.dart';
import '../../i18n/strings.g.dart';

class WidgetsScreen extends StatelessWidget {
  const WidgetsScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? MemoFlowPalette.backgroundDark
        : MemoFlowPalette.backgroundLight;
    final card = isDark ? MemoFlowPalette.cardDark : MemoFlowPalette.cardLight;
    final textMain = isDark
        ? MemoFlowPalette.textDark
        : MemoFlowPalette.textLight;
    final textMuted = textMain.withValues(alpha: isDark ? 0.55 : 0.6);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    Widget content() {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          _Section(
            title: context.t.strings.legacy.msg_random_review,
            textMuted: textMuted,
            child: _WidgetCard(
              card: card,
              border: border,
              preview: _WidgetPreview(
                height: 140,
                isDark: isDark,
                textMuted: textMuted,
                child: const _RandomMemoPreview(),
              ),
              onAdd: () => _handleAdd(context, HomeWidgetType.dailyReview),
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: context.t.strings.legacy.msg_quick_input,
            textMuted: textMuted,
            child: _WidgetCard(
              card: card,
              border: border,
              preview: _WidgetPreview(
                height: 92,
                isDark: isDark,
                textMuted: textMuted,
                child: const _QuickInputPreview(),
              ),
              onAdd: () => _handleAdd(context, HomeWidgetType.quickInput),
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: context.tr(zh: '日历热力图', en: 'Calendar Heatmap'),
            textMuted: textMuted,
            child: _WidgetCard(
              card: card,
              border: border,
              preview: _WidgetPreview(
                height: 164,
                isDark: isDark,
                textMuted: textMuted,
                child: const _CalendarPreview(),
              ),
              onAdd: () => _handleAdd(context, HomeWidgetType.calendar),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'MemoFlow · v1.0.18',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: textMuted.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: showBackButton,
        leading: showBackButton
            ? IconButton(
                tooltip: context.t.strings.legacy.msg_back,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(context.t.strings.legacy.msg_widgets),
        centerTitle: false,
      ),
      body: isDark
          ? Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [const Color(0xFF0B0B0B), bg, bg],
                      ),
                    ),
                  ),
                ),
                content(),
              ],
            )
          : content(),
    );
  }

  static Future<void> _handleAdd(
    BuildContext context,
    HomeWidgetType type,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      showTopToast(
        context,
        context.t.strings.legacy.msg_ios_long_press_home_screen_add,
      );
      return;
    }
    final ok = await HomeWidgetService.requestPinWidget(type);
    if (!context.mounted) return;
    showTopToast(
      context,
      ok
          ? context.t.strings.legacy.msg_request_sent_confirm_system_prompt
          : context.t.strings.legacy.msg_one_tap_add_not_supported_add,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.textMuted,
    required this.child,
  });

  final String title;
  final Color textMuted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: textMuted,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _WidgetCard extends StatefulWidget {
  const _WidgetCard({
    required this.card,
    required this.border,
    required this.preview,
    required this.onAdd,
  });

  final Color card;
  final Color border;
  final Widget preview;
  final VoidCallback onAdd;

  @override
  State<_WidgetCard> createState() => _WidgetCardState();
}

class _WidgetCardState extends State<_WidgetCard> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: widget.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.border),
        boxShadow: isDark
            ? [
                BoxShadow(
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ]
            : [
                BoxShadow(
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                  color: Colors.black.withValues(alpha: 0.06),
                ),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        children: [
          widget.preview,
          const SizedBox(height: 14),
          GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) {
              setState(() => _pressed = false);
              widget.onAdd();
            },
            child: AnimatedScale(
              scale: _pressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 140),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: MemoFlowPalette.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  child: Text(
                    context.t.strings.legacy.msg_add_home_screen,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetPreview extends StatelessWidget {
  const _WidgetPreview({
    required this.height,
    required this.isDark,
    required this.textMuted,
    required this.child,
  });

  final double height;
  final bool isDark;
  final Color textMuted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class _RandomMemoPreview extends StatelessWidget {
  const _RandomMemoPreview();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark
        ? Colors.white.withValues(alpha: 0.75)
        : Colors.black.withValues(alpha: 0.65);
    final card = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t.strings.legacy.msg_random_review,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: text,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(
                    zh: '下雨天坐在窗边，突然想起去年的今天。',
                    en: 'Rain on the window pulled me back to this day last year.',
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '2025-03-12',
                  style: TextStyle(
                    fontSize: 10,
                    color: text.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickInputPreview extends StatelessWidget {
  const _QuickInputPreview();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final field = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);
    final text = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : Colors.black.withValues(alpha: 0.5);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: field,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.t.strings.legacy.msg_what_s,
                style: TextStyle(color: text, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: MemoFlowPalette.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.south_east_rounded,
            size: 18,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _CalendarPreview extends StatelessWidget {
  const _CalendarPreview();

  @override
  Widget build(BuildContext context) {
    const outsideColor = Color(0xFF5A6170);
    const weekColor = Color(0xFF7A8190);
    const dayColor = Color(0xFFD0D5DD);
    const todayBorder = Color(0xFF8D95A3);
    final hot = MemoFlowPalette.primary;
    final labels = <String>[
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      '11',
      '12',
      '13',
      '14',
      '15',
      '16',
      '17',
      '18',
      '19',
      '20',
      '21',
      '22',
      '23',
      '24',
      '25',
      '26',
      '27',
      '28',
      '29',
      '30',
      '31',
      '1',
      '2',
      '3',
      '4',
    ];
    final activeLevels = <int, int>{14: 3, 17: 2, 19: 3};
    const todayIndex = 20;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2B313D)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'March 2026',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF3F5F8),
                    ),
                  ),
                ),
                Text(
                  '? ?',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: weekColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                  .map(
                    (label) => Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: weekColor,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: labels.length,
                itemBuilder: (context, index) {
                  final level = activeLevels[index] ?? 0;
                  final isCurrentMonth = index < 31;
                  final isToday = index == todayIndex;
                  final decoration = level > 0
                      ? BoxDecoration(
                          color: hot.withValues(
                            alpha: switch (level) {
                              3 => 0.82,
                              2 => 0.64,
                              _ => 0.42,
                            },
                          ),
                          shape: BoxShape.circle,
                        )
                      : isToday
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: todayBorder),
                        )
                      : null;
                  final textColor = level > 0
                      ? Colors.white
                      : isCurrentMonth
                      ? (isToday ? Colors.white : dayColor)
                      : outsideColor;
                  return Center(
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: decoration,
                      alignment: Alignment.center,
                      child: Text(
                        labels[index],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
