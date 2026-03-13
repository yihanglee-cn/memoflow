import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/memoflow_palette.dart';
import '../../core/top_toast.dart';
import '../../data/ai/ai_route_config.dart';
import '../../data/repositories/ai_settings_repository.dart';
import '../../state/settings/ai_settings_provider.dart';

class AiRouteSettingsScreen extends ConsumerWidget {
  const AiRouteSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aiSettingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isZh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
    final bg = isDark
        ? MemoFlowPalette.backgroundDark
        : MemoFlowPalette.backgroundLight;
    final card = isDark ? MemoFlowPalette.cardDark : MemoFlowPalette.cardLight;
    final textMain = isDark
        ? MemoFlowPalette.textDark
        : MemoFlowPalette.textLight;
    final textMuted = textMain.withValues(alpha: isDark ? 0.58 : 0.62);
    final generation = AiRouteResolver.resolveTaskRoute(
      services: settings.services,
      bindings: settings.taskRouteBindings,
      routeId: AiTaskRouteId.summary,
      capability: AiCapability.chat,
    );
    final embedding = AiRouteResolver.resolveTaskRoute(
      services: settings.services,
      bindings: settings.taskRouteBindings,
      routeId: AiTaskRouteId.embeddingRetrieval,
      capability: AiCapability.embedding,
    );

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(isZh ? '默认用途' : 'Default Routes'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _RouteTile(
            title: isZh ? '生成默认' : 'Generation Default',
            subtitle: generation == null
                ? (isZh ? '未绑定模型' : 'No model selected')
                : '${generation.service.displayName} · ${generation.model.displayName}',
            card: card,
            textMain: textMain,
            textMuted: textMuted,
            onTap: () => _pickRoute(
              context,
              ref,
              routeIds: const <AiTaskRouteId>[
                AiTaskRouteId.summary,
                AiTaskRouteId.analysisReport,
                AiTaskRouteId.quickPrompt,
              ],
              capability: AiCapability.chat,
            ),
          ),
          const SizedBox(height: 12),
          _RouteTile(
            title: 'Embedding Default',
            subtitle: embedding == null
                ? (isZh ? '未绑定模型' : 'No model selected')
                : '${embedding.service.displayName} · ${embedding.model.displayName}',
            card: card,
            textMain: textMain,
            textMuted: textMuted,
            onTap: () => _pickRoute(
              context,
              ref,
              routeIds: const <AiTaskRouteId>[AiTaskRouteId.embeddingRetrieval],
              capability: AiCapability.embedding,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRoute(
    BuildContext context,
    WidgetRef ref, {
    required List<AiTaskRouteId> routeIds,
    required AiCapability capability,
  }) async {
    final settings = ref.read(aiSettingsProvider);
    final isZh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
    final options = selectableRouteOptionsForCapability(
      settings,
      capability: capability,
    );
    if (options.isEmpty) {
      showTopToast(
        context,
        isZh ? '请先添加可用模型。' : 'Add a compatible model first.',
      );
      return;
    }

    final selected = await showModalBottomSheet<AiSelectableRouteOption>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  isZh ? '选择默认模型' : 'Choose Default Model',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final option in options)
                ListTile(
                  title: Text(option.model.displayName),
                  subtitle: Text(option.service.displayName),
                  onTap: () => Navigator.of(context).pop(option),
                ),
            ],
          ),
        );
      },
    );
    if (selected == null) return;

    final replacements = routeIds
        .map(
          (routeId) => AiTaskRouteBinding(
            routeId: routeId,
            serviceId: selected.service.serviceId,
            modelId: selected.model.modelId,
            capability: capability,
          ),
        )
        .toList(growable: false);
    final current = settings.taskRouteBindings
        .where((binding) => !routeIds.contains(binding.routeId))
        .toList(growable: true)
      ..addAll(replacements);
    await ref
        .read(aiSettingsProvider.notifier)
        .replaceTaskRouteBindings(current);
    if (!context.mounted) return;
    showTopToast(
      context,
      isZh ? '默认用途已更新。' : 'Default routes updated.',
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.title,
    required this.subtitle,
    required this.card,
    required this.textMain,
    required this.textMuted,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color card;
  final Color textMain;
  final Color textMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                      color: Colors.black.withValues(alpha: 0.05),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textMain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
