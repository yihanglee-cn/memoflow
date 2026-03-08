import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/ai/ai_analysis_models.dart'
    show AiRetrievalPreviewItem, AiRetrievalPreviewPayload;
import '../../i18n/strings.g.dart';

enum AiInsightId {
  todayClues,
  emotionMap,
  themeResonance,
  thoughtTrace,
  blindSpotDiscovery,
  relationshipView,
  actionExtraction,
  longTermTrajectory,
}

class AiInsightDefinition {
  const AiInsightDefinition({
    required this.id,
    required this.icon,
    required this.accent,
  });

  final AiInsightId id;
  final IconData icon;
  final Color accent;

  String title(BuildContext context) => switch (id) {
    AiInsightId.todayClues =>
      context.t.strings.aiInsight.cards.todayClues.title,
    AiInsightId.emotionMap =>
      context.t.strings.aiInsight.cards.emotionMap.title,
    AiInsightId.themeResonance =>
      context.t.strings.aiInsight.cards.themeResonance.title,
    AiInsightId.thoughtTrace =>
      context.t.strings.aiInsight.cards.thoughtTrace.title,
    AiInsightId.blindSpotDiscovery =>
      context.t.strings.aiInsight.cards.blindSpotDiscovery.title,
    AiInsightId.relationshipView =>
      context.t.strings.aiInsight.cards.relationshipView.title,
    AiInsightId.actionExtraction =>
      context.t.strings.aiInsight.cards.actionExtraction.title,
    AiInsightId.longTermTrajectory =>
      context.t.strings.aiInsight.cards.longTermTrajectory.title,
  };

  String description(BuildContext context) => switch (id) {
    AiInsightId.todayClues =>
      context.t.strings.aiInsight.cards.todayClues.description,
    AiInsightId.emotionMap =>
      context.t.strings.aiInsight.cards.emotionMap.description,
    AiInsightId.themeResonance =>
      context.t.strings.aiInsight.cards.themeResonance.description,
    AiInsightId.thoughtTrace =>
      context.t.strings.aiInsight.cards.thoughtTrace.description,
    AiInsightId.blindSpotDiscovery =>
      context.t.strings.aiInsight.cards.blindSpotDiscovery.description,
    AiInsightId.relationshipView =>
      context.t.strings.aiInsight.cards.relationshipView.description,
    AiInsightId.actionExtraction =>
      context.t.strings.aiInsight.cards.actionExtraction.description,
    AiInsightId.longTermTrajectory =>
      context.t.strings.aiInsight.cards.longTermTrajectory.description,
  };
}

const aiInsightDefinitions = <AiInsightDefinition>[
  AiInsightDefinition(
    id: AiInsightId.todayClues,
    icon: Icons.search_rounded,
    accent: Color(0xFFE6A468),
  ),
  AiInsightDefinition(
    id: AiInsightId.emotionMap,
    icon: Icons.favorite_rounded,
    accent: Color(0xFFE695AE),
  ),
  AiInsightDefinition(
    id: AiInsightId.themeResonance,
    icon: Icons.auto_awesome_rounded,
    accent: Color(0xFF7DB8E8),
  ),
  AiInsightDefinition(
    id: AiInsightId.thoughtTrace,
    icon: Icons.bubble_chart_rounded,
    accent: Color(0xFF66C9C8),
  ),
  AiInsightDefinition(
    id: AiInsightId.blindSpotDiscovery,
    icon: Icons.visibility_rounded,
    accent: Color(0xFFB7BE64),
  ),
  AiInsightDefinition(
    id: AiInsightId.relationshipView,
    icon: Icons.people_alt_rounded,
    accent: Color(0xFFD9918F),
  ),
  AiInsightDefinition(
    id: AiInsightId.actionExtraction,
    icon: Icons.bolt_rounded,
    accent: Color(0xFFE6A756),
  ),
  AiInsightDefinition(
    id: AiInsightId.longTermTrajectory,
    icon: Icons.show_chart_rounded,
    accent: Color(0xFF72C7C9),
  ),
];

const visibleAiInsightDefinitions = <AiInsightDefinition>[
  AiInsightDefinition(
    id: AiInsightId.emotionMap,
    icon: Icons.favorite_rounded,
    accent: Color(0xFFE695AE),
  ),
];

AiInsightDefinition definitionForInsight(AiInsightId id) {
  return aiInsightDefinitions.firstWhere((definition) => definition.id == id);
}

extension AiInsightIdStorage on AiInsightId {
  String get storageKey => switch (this) {
    AiInsightId.todayClues => 'today_clues',
    AiInsightId.emotionMap => 'emotion_map',
    AiInsightId.themeResonance => 'theme_resonance',
    AiInsightId.thoughtTrace => 'thought_trace',
    AiInsightId.blindSpotDiscovery => 'blind_spot_discovery',
    AiInsightId.relationshipView => 'relationship_view',
    AiInsightId.actionExtraction => 'action_extraction',
    AiInsightId.longTermTrajectory => 'long_term_trajectory',
  };
}

enum AiInsightRange { last3Days, last7Days, last30Days, custom }

extension AiInsightRangeLabel on AiInsightRange {
  String label(BuildContext context) => switch (this) {
    AiInsightRange.last3Days => context.t.strings.aiInsight.timeRange.last3Days,
    AiInsightRange.last7Days => context.t.strings.aiInsight.timeRange.last7Days,
    AiInsightRange.last30Days =>
      context.t.strings.aiInsight.timeRange.last30Days,
    AiInsightRange.custom => context.t.strings.aiInsight.timeRange.customRange,
  };
}

DateTimeRange resolveAiInsightRange(
  AiInsightRange range,
  DateTimeRange? customRange, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  if (range == AiInsightRange.custom && customRange != null) {
    return customRange;
  }
  if (range == AiInsightRange.last30Days) {
    return DateTimeRange(
      start: today.subtract(const Duration(days: 29)),
      end: today,
    );
  }
  if (range == AiInsightRange.last3Days) {
    return DateTimeRange(
      start: today.subtract(const Duration(days: 2)),
      end: today,
    );
  }
  return DateTimeRange(
    start: today.subtract(const Duration(days: 6)),
    end: today,
  );
}

String formatAiInsightRangeLabel(
  DateTimeRange range, {
  String pattern = 'yyyy.MM.dd',
}) {
  final formatter = DateFormat(pattern);
  return '${formatter.format(range.start)} - ${formatter.format(range.end)}';
}

String formatAiInsightReportRangeLabel(
  BuildContext context,
  DateTimeRange range,
) {
  final locale = Localizations.localeOf(context).toString();
  final sameYear = range.start.year == range.end.year;
  final sameMonth = sameYear && range.start.month == range.end.month;
  final startFormatter = sameYear
      ? DateFormat.MMMd(locale)
      : DateFormat.yMMMd(locale);
  final endFormatter = sameYear
      ? (sameMonth ? DateFormat.d(locale) : DateFormat.MMMd(locale))
      : DateFormat.yMMMd(locale);
  return '${startFormatter.format(range.start)} - ${endFormatter.format(range.end)}';
}

int estimateAiInsightTokens(String payloadText) {
  if (payloadText.trim().isEmpty) return 0;
  return (utf8.encode(payloadText).length / 4).ceil();
}

typedef AiPreviewMemoItem = AiRetrievalPreviewItem;
typedef AiAnalysisPreviewPayload = AiRetrievalPreviewPayload;

class AiInsightSettingsResult {
  const AiInsightSettingsResult({
    required this.insightId,
    required this.range,
    required this.customRange,
    required this.allowPublic,
    required this.allowPrivate,
    required this.allowProtected,
    required this.previewPayload,
    required this.promptTemplate,
  });

  final AiInsightId insightId;
  final AiInsightRange range;
  final DateTimeRange? customRange;
  final bool allowPublic;
  final bool allowPrivate;
  final bool allowProtected;
  final AiAnalysisPreviewPayload previewPayload;
  final String promptTemplate;
}
