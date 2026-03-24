import 'dart:convert';

import 'package:path/path.dart' as p;

import 'share_clip_models.dart';

const String _thirdPartyShareMemoMarker = '<!-- memoflow-third-party-share -->';

String shareInlineLocalUrlFromPath(String filePath) {
  final trimmed = filePath.trim();
  if (trimmed.isEmpty) return '';
  return Uri.file(trimmed).toString();
}

String buildThirdPartyShareMemoMarker() => _thirdPartyShareMemoMarker;

bool contentHasThirdPartyShareMarker(String content) {
  return content.contains(_thirdPartyShareMemoMarker);
}

String buildShareInlineImagePlaceholder(String uid) {
  return '<!-- memoflow-share-inline:$uid -->';
}

String buildShareInlineSyncContent(
  String content,
  Iterable<ShareAttachmentSeed> attachments,
) {
  var next = content;
  for (final attachment in attachments) {
    if (!attachment.shareInlineImage) continue;
    final localUrl = shareInlineLocalUrlFromPath(attachment.filePath);
    if (localUrl.isEmpty) continue;
    final placeholder = buildShareInlineImagePlaceholder(attachment.uid);
    next = _replaceHtmlImageTag(next, localUrl, placeholder);
    next = _replaceMarkdownImage(next, localUrl, placeholder);
  }
  return next;
}

String replaceShareInlineLocalUrlWithRemote(
  String content, {
  required String localUrl,
  required String remoteUrl,
}) {
  if (localUrl.trim().isEmpty || remoteUrl.trim().isEmpty) {
    return content;
  }
  return replaceShareInlineImageUrl(
    content,
    fromUrl: localUrl,
    toUrl: remoteUrl,
  );
}

String replaceShareInlineImageUrl(
  String content, {
  required String fromUrl,
  required String toUrl,
}) {
  if (fromUrl.trim().isEmpty || toUrl.trim().isEmpty) {
    return content;
  }
  var next = content;
  final rawFromUrl = fromUrl.trim();
  final rawToUrl = toUrl.trim();
  final escapedToUrl = _escapeHtmlAttribute(rawToUrl);
  for (final variant in _shareInlineImageUrlVariants(rawFromUrl)) {
    next = next.replaceAll(
      variant,
      variant == rawFromUrl ? rawToUrl : escapedToUrl,
    );
  }
  return next;
}

bool contentContainsShareInlineImageUrl(String content, String url) {
  final trimmedUrl = url.trim();
  if (trimmedUrl.isEmpty) return false;
  for (final variant in _shareInlineImageUrlVariants(trimmedUrl)) {
    if (content.contains(variant)) {
      return true;
    }
  }
  return false;
}

String removeShareInlineImageReferences(
  String content, {
  required String localUrl,
}) {
  if (localUrl.trim().isEmpty) return content;
  var next = _replaceHtmlImageTag(content, localUrl, '');
  next = _replaceMarkdownImage(next, localUrl, '');
  return _cleanupBlankLines(next);
}

bool contentContainsShareInlineLocalUrl(String content, String filePath) {
  final localUrl = shareInlineLocalUrlFromPath(filePath);
  if (localUrl.isEmpty) return false;
  return content.contains(localUrl);
}

String buildShareInlineImageFilename({
  required int index,
  required String sourceUrl,
  String? mimeType,
}) {
  final parsed = Uri.tryParse(sourceUrl);
  final rawName = parsed?.pathSegments.isNotEmpty == true
      ? parsed!.pathSegments.last
      : 'shared-inline-image';
  final ext = _resolveImageExtension(sourceUrl, mimeType);
  final baseName = p.basenameWithoutExtension(rawName).trim();
  final safeBase = baseName.isEmpty
      ? 'shared_inline_image_${index + 1}'
      : baseName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return '$safeBase$ext';
}

String _replaceHtmlImageTag(
  String content,
  String localUrl,
  String replacement,
) {
  final escaped = RegExp.escape(localUrl);
  final pattern = RegExp(
    '<img\\b[^>]*\\bsrc=("|\')$escaped\\1[^>]*>',
    caseSensitive: false,
  );
  return content.replaceAll(pattern, replacement);
}

String _replaceMarkdownImage(
  String content,
  String localUrl,
  String replacement,
) {
  final escaped = RegExp.escape(localUrl);
  final pattern = RegExp(
    '!\\[[^\\]]*\\]\\(<?$escaped>?(?:\\s+"[^"]*")?\\)',
    caseSensitive: false,
  );
  return content.replaceAll(pattern, replacement);
}

String _cleanupBlankLines(String content) {
  return content
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .trimRight();
}

Iterable<String> _shareInlineImageUrlVariants(String url) sync* {
  final variants = <String>{};
  final trimmed = url.trim();
  if (trimmed.isEmpty) return;
  variants.add(trimmed);
  variants.add(_escapeHtmlAttribute(trimmed));
  for (final variant in variants) {
    if (variant.isNotEmpty) {
      yield variant;
    }
  }
}

String _escapeHtmlAttribute(String value) {
  return const HtmlEscape(HtmlEscapeMode.attribute).convert(value);
}

String _resolveImageExtension(String sourceUrl, String? mimeType) {
  final parsed = Uri.tryParse(sourceUrl);
  final path = parsed?.path.toLowerCase() ?? sourceUrl.toLowerCase();
  for (final ext in const ['.jpg', '.jpeg', '.png', '.webp', '.gif']) {
    if (path.contains(ext)) return ext;
  }
  final wxFormat = parsed?.queryParameters['wx_fmt']?.trim().toLowerCase();
  switch (wxFormat) {
    case 'jpeg':
    case 'jpg':
      return '.jpg';
    case 'png':
      return '.png';
    case 'webp':
      return '.webp';
    case 'gif':
      return '.gif';
  }
  final normalizedMime = (mimeType ?? '').trim().toLowerCase();
  if (normalizedMime.contains('png')) return '.png';
  if (normalizedMime.contains('webp')) return '.webp';
  if (normalizedMime.contains('gif')) return '.gif';
  return '.jpg';
}
