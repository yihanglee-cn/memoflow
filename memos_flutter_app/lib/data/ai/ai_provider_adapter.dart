import 'ai_provider_models.dart';

class AiChatMessage {
  const AiChatMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class AiChatCompletionRequest {
  const AiChatCompletionRequest({
    required this.service,
    required this.model,
    required this.messages,
    this.systemPrompt,
    this.temperature,
    this.maxOutputTokens,
  });

  final AiServiceInstance service;
  final AiModelEntry model;
  final List<AiChatMessage> messages;
  final String? systemPrompt;
  final double? temperature;
  final int? maxOutputTokens;
}

class AiChatCompletionResult {
  const AiChatCompletionResult({required this.text, required this.raw});

  final String text;
  final Object? raw;
}

class AiEmbeddingRequest {
  const AiEmbeddingRequest({
    required this.service,
    required this.model,
    required this.input,
  });

  final AiServiceInstance service;
  final AiModelEntry model;
  final String input;
}

class AiDiscoveredModel {
  const AiDiscoveredModel({
    required this.displayName,
    required this.modelKey,
    required this.capabilities,
    this.ownedBy,
  });

  final String displayName;
  final String modelKey;
  final List<AiCapability> capabilities;
  final String? ownedBy;
}

class AiServiceValidationResult {
  const AiServiceValidationResult({required this.status, this.message});

  final AiValidationStatus status;
  final String? message;
}

abstract class AiProviderAdapter {
  Future<AiServiceValidationResult> validateConfig(AiServiceInstance service);

  Future<List<AiDiscoveredModel>> listModels(AiServiceInstance service);

  Future<AiChatCompletionResult> chatCompletion(
    AiChatCompletionRequest request,
  );

  Future<List<double>> embed(AiEmbeddingRequest request);
}
