import 'package:dio/dio.dart';

import '../../../core/log_sanitizer.dart';
import '../../logs/log_manager.dart';
import '../ai_provider_models.dart';
import '../ai_settings_log.dart';

enum AiProviderRequestTimeoutProfile { short, embedding, chatCompletion }

Dio buildAiProviderDio(
  AiServiceInstance service, {
  AiProviderRequestTimeoutProfile profile =
      AiProviderRequestTimeoutProfile.short,
}) {
  final receiveTimeout = switch (profile) {
    AiProviderRequestTimeoutProfile.short => const Duration(seconds: 20),
    AiProviderRequestTimeoutProfile.embedding => const Duration(seconds: 45),
    AiProviderRequestTimeoutProfile.chatCompletion => const Duration(
      seconds: 180,
    ),
  };
  final sendTimeout = switch (profile) {
    AiProviderRequestTimeoutProfile.short => const Duration(seconds: 20),
    AiProviderRequestTimeoutProfile.embedding => const Duration(seconds: 30),
    AiProviderRequestTimeoutProfile.chatCompletion => const Duration(
      seconds: 60,
    ),
  };
  return Dio(
    BaseOptions(
      headers: Map<String, String>.from(service.customHeaders),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      responseType: ResponseType.json,
      validateStatus: (status) => status != null && status < 500,
    ),
  );
}

String normalizeBaseUrl(String baseUrl) {
  return baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
}

String ensureVersionSegment(String baseUrl, String segment) {
  final normalizedBase = normalizeBaseUrl(baseUrl);
  if (normalizedBase.isEmpty) return normalizedBase;
  final normalizedSegment = segment.replaceFirst(RegExp(r'^/+'), '');
  if (normalizedBase.endsWith('/$normalizedSegment')) {
    return normalizedBase;
  }
  return '$normalizedBase/$normalizedSegment';
}

String resolveEndpoint(String baseUrl, String path) {
  final normalizedBase = normalizeBaseUrl(baseUrl);
  final normalizedPath = path.replaceFirst(RegExp(r'^/+'), '');
  if (normalizedBase.isEmpty) return normalizedPath;
  return '$normalizedBase/$normalizedPath';
}

Stopwatch logAiProviderRequestStarted(
  AiServiceInstance service, {
  required String operation,
  required String method,
  required String endpoint,
  Map<String, Object?>? queryParameters,
  Map<String, String>? requestHeaders,
}) {
  final stopwatch = Stopwatch()..start();
  LogManager.instance.info(
    'AI adapter request started',
    context: _buildAiProviderRequestLogContext(
      service,
      operation: operation,
      method: method,
      endpoint: endpoint,
      queryParameters: queryParameters,
      requestHeaders: requestHeaders,
    ),
  );
  return stopwatch;
}

void logAiProviderRequestFinished(
  AiServiceInstance service,
  Stopwatch stopwatch, {
  required String operation,
  required String method,
  required String endpoint,
  Map<String, Object?>? queryParameters,
  Map<String, String>? requestHeaders,
  int? statusCode,
  int? discoveredCount,
  String? responseMessage,
}) {
  if (stopwatch.isRunning) {
    stopwatch.stop();
  }
  LogManager.instance.info(
    'AI adapter request finished',
    context: _buildAiProviderRequestLogContext(
      service,
      operation: operation,
      method: method,
      endpoint: endpoint,
      queryParameters: queryParameters,
      requestHeaders: requestHeaders,
      statusCode: statusCode,
      elapsedMs: stopwatch.elapsedMilliseconds,
      discoveredCount: discoveredCount,
      responseMessage: responseMessage,
    ),
  );
}

void logAiProviderRequestFailed(
  AiServiceInstance service,
  Stopwatch stopwatch, {
  required String operation,
  required String method,
  required String endpoint,
  Map<String, Object?>? queryParameters,
  Map<String, String>? requestHeaders,
  int? statusCode,
  Object? error,
  StackTrace? stackTrace,
  String? responseMessage,
}) {
  if (stopwatch.isRunning) {
    stopwatch.stop();
  }
  final resolvedStatusCode =
      statusCode ?? (error is DioException ? error.response?.statusCode : null);
  LogManager.instance.warn(
    'AI adapter request failed',
    error: error,
    stackTrace: stackTrace,
    context: _buildAiProviderRequestLogContext(
      service,
      operation: operation,
      method: method,
      endpoint: endpoint,
      queryParameters: queryParameters,
      requestHeaders: requestHeaders,
      statusCode: resolvedStatusCode,
      elapsedMs: stopwatch.elapsedMilliseconds,
      responseMessage: responseMessage,
    ),
  );
}

void logAiProviderRequestUnsupported(
  AiServiceInstance service, {
  required String operation,
  required String method,
  required String endpoint,
  Map<String, Object?>? queryParameters,
  Map<String, String>? requestHeaders,
  String? reason,
}) {
  LogManager.instance.info(
    'AI adapter request unsupported',
    context: _buildAiProviderRequestLogContext(
      service,
      operation: operation,
      method: method,
      endpoint: endpoint,
      queryParameters: queryParameters,
      requestHeaders: requestHeaders,
      responseMessage: reason,
    ),
  );
}

String extractErrorMessage(
  Object error, {
  String fallback = 'Request failed.',
}) {
  if (error is DioException) {
    final response = error.response;
    if (response != null) {
      return errorMessageFromResponse(response.data, fallback: fallback);
    }
    return error.message?.trim().isNotEmpty == true
        ? error.message!.trim()
        : fallback;
  }
  final message = error.toString().trim();
  if (message.isEmpty) return fallback;
  return message.replaceFirst('Exception: ', '');
}

String errorMessageFromResponse(
  Object? data, {
  String fallback = 'Request failed.',
}) {
  if (data is Map) {
    final directMessage = _readMessage(data);
    if (directMessage != null) return directMessage;
    final error = data['error'];
    if (error is Map) {
      final nestedMessage = _readMessage(error);
      if (nestedMessage != null) return nestedMessage;
    }
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }
  }
  if (data is String && data.trim().isNotEmpty) {
    return data.trim();
  }
  return fallback;
}

String? _readMessage(Map data) {
  for (final key in const <String>['message', 'detail', 'error_msg', 'code']) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

Map<String, Object?> _buildAiProviderRequestLogContext(
  AiServiceInstance service, {
  required String operation,
  required String method,
  required String endpoint,
  Map<String, Object?>? queryParameters,
  Map<String, String>? requestHeaders,
  int? statusCode,
  int? elapsedMs,
  int? discoveredCount,
  String? responseMessage,
}) {
  return <String, Object?>{
    ...buildAiServiceLogContext(
      service,
      endpoint: endpoint,
      discoveredCount: discoveredCount,
    ),
    'operation': operation,
    'method': method.toUpperCase(),
    if (requestHeaders != null) 'request_header_count': requestHeaders.length,
    if (requestHeaders != null && requestHeaders.isNotEmpty)
      'request_headers': LogSanitizer.sanitizeHeaders(requestHeaders),
    if (queryParameters != null) 'query_param_count': queryParameters.length,
    if (queryParameters != null && queryParameters.isNotEmpty)
      'query_params': LogSanitizer.sanitizeJson(queryParameters),
    if (statusCode != null) 'status_code': statusCode,
    if (elapsedMs != null) 'elapsed_ms': elapsedMs,
    if (responseMessage != null && responseMessage.trim().isNotEmpty)
      'response_message': LogSanitizer.sanitizeText(responseMessage.trim()),
  };
}

List<AiCapability> inferOpenAiCompatibleCapabilities(String modelKey) {
  final normalized = modelKey.trim().toLowerCase();
  if (normalized.contains('embed') || normalized.contains('embedding')) {
    return const <AiCapability>[AiCapability.embedding];
  }
  return const <AiCapability>[AiCapability.chat];
}

List<AiCapability> inferOllamaCapabilities(String modelKey) {
  final normalized = modelKey.trim().toLowerCase();
  if (normalized.contains('embed') || normalized.contains('embedding')) {
    return const <AiCapability>[AiCapability.embedding];
  }
  return const <AiCapability>[AiCapability.chat];
}
