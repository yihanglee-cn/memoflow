import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'share_clip_models.dart';
import 'share_handler.dart';

const Set<String> _blockedHtmlTags = {'script', 'style', 'noscript'};

const Set<String> _allowedHtmlTags = {
  'a',
  'blockquote',
  'br',
  'code',
  'del',
  'details',
  'em',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'img',
  'input',
  'li',
  'ol',
  'p',
  'pre',
  'summary',
  'span',
  'strong',
  'sub',
  'sup',
  'table',
  'tbody',
  'td',
  'th',
  'thead',
  'tr',
  'ul',
};

const Map<String, Set<String>> _allowedHtmlAttributes = {
  'a': {'href', 'title'},
  'img': {'src', 'alt', 'title', 'width', 'height'},
  'code': {'class'},
  'pre': {'class'},
  'span': {'class'},
  'li': {'class'},
  'ul': {'class'},
  'ol': {'class'},
  'p': {'class'},
  'details': {'open'},
  'input': {'type', 'checked', 'disabled'},
};

const Set<String> _voidHtmlTags = {'br', 'hr', 'img', 'input'};

ShareComposeRequest buildShareComposeRequestFromCapture({
  required ShareCaptureResult result,
  required SharePayload payload,
  List<String> attachmentPaths = const [],
  String? userMessage,
}) {
  final text = buildShareCaptureMemoText(result: result, payload: payload);
  return ShareComposeRequest(
    text: text,
    selectionOffset: text.length,
    attachmentPaths: attachmentPaths,
    userMessage: userMessage,
  );
}

ShareComposeRequest buildLinkOnlyComposeRequest(SharePayload payload) {
  final draft = buildShareTextDraft(payload);
  return ShareComposeRequest(
    text: draft.text,
    selectionOffset: draft.selectionOffset,
  );
}

String buildShareCaptureMemoText({
  required ShareCaptureResult result,
  required SharePayload payload,
}) {
  if (result.pageKind == SharePageKind.video) {
    return _buildShareVideoMemoText(result: result, payload: payload);
  }

  final resolvedUrl = _resolveFinalUrl(result.finalUrl);
  final title = _resolveTitle(result: result, payload: payload, url: resolvedUrl);
  final siteLabel = _resolveSiteLabel(result: result, url: resolvedUrl);
  final excerpt = _normalizeWhitespace(result.excerpt);
  final fragment = _buildHtmlFragment(result: result, baseUrl: resolvedUrl);
  final buffer = StringBuffer()..writeln('# $title')..writeln();
  final linkLabel = title.isNotEmpty ? title : siteLabel;
  buffer.writeln(_buildMarkdownLink(linkLabel, resolvedUrl));
  if (excerpt != null) {
    buffer..writeln()..writeln('> $excerpt');
  }
  if (fragment != null) {
    buffer..writeln()..writeln(fragment);
  }
  return buffer.toString().trimRight();
}

String _buildShareVideoMemoText({
  required ShareCaptureResult result,
  required SharePayload payload,
}) {
  final resolvedUrl = _resolveFinalUrl(result.finalUrl);
  final title = _resolveTitle(result: result, payload: payload, url: resolvedUrl);
  final excerpt = _normalizeWhitespace(result.excerpt);
  final buffer = StringBuffer()..writeln('# $title')..writeln();
  buffer.writeln(_buildMarkdownLink(title, resolvedUrl));
  if (excerpt != null) {
    buffer..writeln()..writeln('> $excerpt');
  }
  return buffer.toString().trimRight();
}

String _buildMarkdownLink(String label, Uri url) {
  return '[${_escapeMarkdownText(label)}](${url.toString()})';
}

String _resolveTitle({
  required ShareCaptureResult result,
  required SharePayload payload,
  required Uri url,
}) {
  return _normalizeWhitespace(result.articleTitle) ??
      _normalizeWhitespace(payload.title) ??
      _normalizeWhitespace(result.pageTitle) ??
      url.host;
}

String _resolveSiteLabel({
  required ShareCaptureResult result,
  required Uri url,
}) {
  return _normalizeWhitespace(result.siteName) ?? url.host;
}

Uri _resolveFinalUrl(Uri url) {
  if (url.hasScheme && url.hasAuthority) return url;
  final normalized = Uri.tryParse(url.toString());
  if (normalized != null && normalized.hasScheme && normalized.hasAuthority) {
    return normalized;
  }
  return Uri.parse('https://${url.toString()}');
}

String? _buildHtmlFragment({
  required ShareCaptureResult result,
  required Uri baseUrl,
}) {
  final rawHtml = (result.contentHtml ?? '').trim();
  if (rawHtml.isNotEmpty) {
    return _sanitizeFragment(rawHtml, baseUrl);
  }

  final fallback = _buildTextFallback(result.textContent);
  if (fallback.isEmpty) return null;
  return fallback;
}

String? _sanitizeFragment(String rawHtml, Uri baseUrl) {
  final fragment = html_parser.parseFragment(rawHtml);
  _absolutizeAttribute(fragment, tagName: 'a', attribute: 'href', baseUrl: baseUrl);
  _absolutizeAttribute(fragment, tagName: 'img', attribute: 'src', baseUrl: baseUrl);
  final sanitized = _sanitizeFragmentToHtml(fragment).trim();
  if (sanitized.isEmpty) return null;
  return sanitized;
}

String _sanitizeFragmentToHtml(dom.DocumentFragment fragment) {
  return fragment.nodes.map(_sanitizeNodeToHtml).join();
}

String _sanitizeNodeToHtml(dom.Node node) {
  if (node.nodeType == dom.Node.COMMENT_NODE) {
    return '';
  }
  if (node is dom.Text) {
    return node.text;
  }
  if (node is! dom.Element) {
    return node.text ?? '';
  }
  final tag = node.localName;
  if (tag == null || _blockedHtmlTags.contains(tag)) {
    return '';
  }
  if (!_allowedHtmlTags.contains(tag)) {
    return node.nodes.map(_sanitizeNodeToHtml).join();
  }
  final attributes = _sanitizeAttributeMap(node, tag);
  if (attributes == null) {
    return tag == 'img' || tag == 'input'
        ? ''
        : node.nodes.map(_sanitizeNodeToHtml).join();
  }
  final renderedAttributes = attributes.entries
      .map((entry) => ' ${entry.key}="${_escapeHtmlAttribute(entry.value)}"')
      .join();
  if (_voidHtmlTags.contains(tag)) {
    return '<$tag$renderedAttributes>';
  }
  final children = node.nodes.map(_sanitizeNodeToHtml).join();
  return '<$tag$renderedAttributes>$children</$tag>';
}

Map<String, String>? _sanitizeAttributeMap(dom.Element element, String tag) {
  final allowedAttributes = _allowedHtmlAttributes[tag] ?? const <String>{};
  final originalAttributes = Map<String, String>.from(element.attributes);
  final sanitizedAttributes = <String, String>{};
  for (final entry in originalAttributes.entries) {
    if (!allowedAttributes.contains(entry.key)) continue;
    sanitizedAttributes[entry.key] = entry.value;
  }

  if (tag == 'a') {
    final href = _sanitizeUrl(sanitizedAttributes['href'], allowMailto: true);
    if (href == null) {
      return null;
    }
    sanitizedAttributes['href'] = href;
  }

  if (tag == 'img') {
    final src = _sanitizeUrl(sanitizedAttributes['src']);
    if (src == null) {
      return null;
    }
    sanitizedAttributes['src'] = src;
  }

  if (tag == 'input') {
    final type = sanitizedAttributes['type']?.toLowerCase();
    if (type != 'checkbox') {
      return null;
    }
    sanitizedAttributes['type'] = type!;
  }

  return sanitizedAttributes;
}

String? _sanitizeUrl(String? value, {bool allowMailto = false}) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.hasScheme) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') return trimmed;
    if (allowMailto && scheme == 'mailto') return trimmed;
    return null;
  }
  return trimmed;
}

String _escapeHtmlAttribute(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

void _absolutizeAttribute(
  dom.DocumentFragment fragment, {
  required String tagName,
  required String attribute,
  required Uri baseUrl,
}) {
  for (final element in fragment.querySelectorAll('$tagName[$attribute]')) {
    final rawValue = element.attributes[attribute]?.trim();
    if (rawValue == null || rawValue.isEmpty) continue;
    final parsed = Uri.tryParse(rawValue);
    if (parsed == null) continue;
    final resolved = parsed.hasScheme ? parsed : baseUrl.resolveUri(parsed);
    element.attributes[attribute] = resolved.toString();
  }
}

String _buildTextFallback(String? value) {
  final text = value?.replaceAll('\r\n', '\n').trim() ?? '';
  if (text.isEmpty) return '';
  final paragraphs = text
      .split(RegExp(r'\n\s*\n'))
      .map((item) => _normalizeWhitespace(item.replaceAll('\n', ' ')))
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .take(8)
      .toList(growable: false);
  if (paragraphs.isEmpty) return '';

  final buffer = StringBuffer();
  var consumedChars = 0;
  for (final paragraph in paragraphs) {
    if (consumedChars >= 4000) break;
    final available = 4000 - consumedChars;
    final clipped = paragraph.length <= available
        ? paragraph
        : '${paragraph.substring(0, available).trimRight()}...';
    if (clipped.isEmpty) continue;
    if (buffer.isNotEmpty) buffer.writeln('\n');
    buffer.writeln('<p>${_escapeHtml(clipped)}</p>');
    consumedChars += clipped.length;
  }
  return buffer.toString().trim();
}

String _escapeMarkdownText(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');
}

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String? _normalizeWhitespace(String? value) {
  if (value == null) return null;
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized.isEmpty ? null : normalized;
}
