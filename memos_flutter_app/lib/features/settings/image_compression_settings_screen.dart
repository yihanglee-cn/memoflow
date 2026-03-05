import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_localization.dart';
import '../../core/memoflow_palette.dart';
import '../../data/models/image_compression_settings.dart';
import '../../state/settings/image_compression_settings_provider.dart';
import '../../i18n/strings.g.dart';

class ImageCompressionSettingsScreen extends ConsumerWidget {
  const ImageCompressionSettingsScreen({super.key});

  static const int _maxSideStep = 160;
  static const int _qualityStep = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(imageCompressionSettingsProvider);
    final notifier = ref.read(imageCompressionSettingsProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? MemoFlowPalette.backgroundDark
        : MemoFlowPalette.backgroundLight;
    final card = isDark ? MemoFlowPalette.cardDark : MemoFlowPalette.cardLight;
    final textMain =
        isDark ? MemoFlowPalette.textDark : MemoFlowPalette.textLight;
    final textMuted = textMain.withValues(alpha: isDark ? 0.55 : 0.6);
    final divider =
        isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: context.t.strings.legacy.msg_back,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(context.t.strings.legacy.msg_image_compression),
        centerTitle: false,
      ),
      body: Stack(
        children: [
          if (isDark)
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
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _ToggleCard(
                card: card,
                textMain: textMain,
                textMuted: textMuted,
                label: context.t.strings.legacy.msg_enable_image_compression,
                description: context.t.strings.legacy.msg_image_compression_desc,
                value: settings.enabled,
                onChanged: notifier.setEnabled,
              ),
              const SizedBox(height: 16),
              Text(
                context.t.strings.legacy.msg_basics,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textMuted,
                ),
              ),
              const SizedBox(height: 10),
              _Group(
                card: card,
                divider: divider,
                children: [
                  _StepperRow(
                    label: context.t.strings.legacy.msg_max_side,
                    value: settings.maxSide,
                    unit: 'px',
                    textMain: textMain,
                    textMuted: textMuted,
                    onDecrease: () =>
                        notifier.setMaxSide(settings.maxSide - _maxSideStep),
                    onIncrease: () =>
                        notifier.setMaxSide(settings.maxSide + _maxSideStep),
                  ),
                  _StepperRow(
                    label: context.t.strings.legacy.msg_quality,
                    value: settings.quality,
                    unit: '%',
                    textMain: textMain,
                    textMuted: textMuted,
                    onDecrease: () =>
                        notifier.setQuality(settings.quality - _qualityStep),
                    onIncrease: () =>
                        notifier.setQuality(settings.quality + _qualityStep),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                context.t.strings.legacy.msg_output_format,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textMuted,
                ),
              ),
              const SizedBox(height: 10),
              _Group(
                card: card,
                divider: divider,
                children: [
                  _SelectRow(
                    label: context.t.strings.legacy.msg_output_format,
                    value: _formatLabel(context, settings.format),
                    textMain: textMain,
                    textMuted: textMuted,
                    onTap: () => _selectFormat(context, settings.format, notifier),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                context.t.strings.legacy.msg_image_compression_scope,
                style: TextStyle(fontSize: 12, height: 1.35, color: textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatLabel(BuildContext context, ImageCompressionFormat format) {
    return switch (format) {
      ImageCompressionFormat.auto =>
        context.t.strings.legacy.msg_format_auto,
      ImageCompressionFormat.jpeg =>
        context.t.strings.legacy.msg_format_jpeg,
      ImageCompressionFormat.webp =>
        context.t.strings.legacy.msg_format_webp,
    };
  }

  Future<void> _selectFormat(
    BuildContext context,
    ImageCompressionFormat current,
    ImageCompressionSettingsController notifier,
  ) async {
    final selected = await showModalBottomSheet<ImageCompressionFormat>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              _formatTile(
                context,
                label: context.t.strings.legacy.msg_format_auto,
                value: ImageCompressionFormat.auto,
                current: current,
              ),
              _formatTile(
                context,
                label: context.t.strings.legacy.msg_format_jpeg,
                value: ImageCompressionFormat.jpeg,
                current: current,
              ),
              _formatTile(
                context,
                label: context.t.strings.legacy.msg_format_webp,
                value: ImageCompressionFormat.webp,
                current: current,
              ),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    notifier.setFormat(selected);
  }

  ListTile _formatTile(
    BuildContext context, {
    required String label,
    required ImageCompressionFormat value,
    required ImageCompressionFormat current,
  }) {
    return ListTile(
      title: Text(label),
      trailing: current == value ? const Icon(Icons.check) : null,
      onTap: () => context.safePop(value),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.card,
    required this.divider,
    required this.children,
  });

  final Color card;
  final Color divider;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                  color: Colors.black.withValues(alpha: 0.06),
                ),
              ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) Divider(height: 1, color: divider),
          ],
        ],
      ),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.card,
    required this.textMain,
    required this.textMuted,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final Color card;
  final Color textMain;
  final Color textMuted;
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                  color: Colors.black.withValues(alpha: 0.06),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w700, color: textMain),
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
          if (description.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 44),
              child: Text(
                description,
                style: TextStyle(fontSize: 12, color: textMuted, height: 1.3),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.label,
    required this.value,
    required this.textMain,
    required this.textMuted,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color textMain;
  final Color textMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: textMain),
                ),
              ),
              Text(
                value,
                style: TextStyle(fontWeight: FontWeight.w600, color: textMuted),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.textMain,
    required this.textMuted,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final int value;
  final String unit;
  final Color textMain;
  final Color textMuted;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pillBg =
        isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04);
    final pillBorder =
        isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08);

    Widget buildButton(IconData icon, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: textMuted),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: textMain),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: pillBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildButton(Icons.remove, onDecrease),
                const SizedBox(width: 6),
                Text(
                  '$value$unit',
                  style: TextStyle(fontWeight: FontWeight.w700, color: textMain),
                ),
                const SizedBox(width: 6),
                buildButton(Icons.add, onIncrease),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
