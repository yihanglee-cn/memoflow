import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../share_clip_models.dart';

class WechatArticleContentCleanupResult {
  const WechatArticleContentCleanupResult({
    this.contentHtml,
    this.textContent,
    this.excerpt,
  });

  final String? contentHtml;
  final String? textContent;
  final String? excerpt;
}

WechatArticleContentCleanupResult cleanWechatArticleContent({
  required String? rawHtml,
  String? fallbackTextContent,
  String? fallbackExcerpt,
}) {
  final normalizedHtml = normalizeShareText(rawHtml);
  if (normalizedHtml == null) {
    final cleanedText = _normalizeText(fallbackTextContent);
    return WechatArticleContentCleanupResult(
      textContent: cleanedText,
      excerpt: _resolveExcerpt(cleanedText, fallbackExcerpt),
    );
  }

  final fragment = html_parser.parseFragment(normalizedHtml);
  _promoteWechatLazyImageSources(fragment);
  _removeBrokenWechatImageTextTails(fragment);
  _removeKnownWechatNoise(fragment);
  _unwrapRedundantInlineTags(fragment);
  _trimWechatLeadingNoise(fragment);
  _trimWechatTrailingNoise(fragment);
  _removeEmptyElements(fragment);

  final cleanedHtml = normalizeShareText(
    fragment.nodes.map(_serializeNodeHtml).join(),
  );
  final cleanedText = _normalizeText(fragment.text);

  return WechatArticleContentCleanupResult(
    contentHtml: cleanedHtml,
    textContent: cleanedText,
    excerpt: _resolveExcerpt(cleanedText, fallbackExcerpt),
  );
}

const List<String> _wechatNoiseSelectors = [
  'script',
  'style',
  'noscript',
  'iframe',
  'mp-common-profile',
  'qqmusic',
  '.js_ad_link',
  '.original_area_primary',
  '.reward_area',
  '.reward_qrcode_area',
  '.profile_container',
  '.wx_profile_card_inner',
  '.wx_profile_card',
  '.js_profile_container',
  '.js_profile_qrcode',
  '#js_tags',
  '#js_pc_qr_code',
  '#js_share_content',
  '#js_preview_reward_author',
  '#js_read_area3',
  '#js_more_article',
  '#js_article_card',
  '#js_follow_card',
  '#js_copyright_info',
];

const Set<String> _inlineTagsToUnwrap = {'span', 'font'};
const Set<String> _voidOrMediaTags = {'br', 'hr', 'img'};
const Set<String> _wechatLazyImageAttributes = {
  'data-src',
  'data-lazy-src',
  'data-actualsrc',
  'data-original',
};
final RegExp _wechatBrokenImageTailPattern = RegExp(
  r'''#imgIndex=\d+(?:[^<>\s"']*)?(?:\s+(?:alt|title)=["'][^"']*["'])?\s*>?''',
  caseSensitive: false,
);
const Set<String> _wechatPromoKeywords = {
  '点击小程序',
  '立即订阅',
  '拼团',
  '后台回复',
  '预约直播',
  '点亮',
  '在看',
  '分享',
  '星标',
  '教程',
};
const List<String> _wechatHardStopPhrases = [
  '点击小程序，立即订阅',
  '可直接参与拼团',
  '24小时内拼团不成功自动退款',
  '苹果用户后台回复',
  '点亮「在看」',
  '点亮“在看”',
  '「在看」+「分享」',
  '“在看”+“分享”',
  '作 者 /',
  '插 画 /',
  '运 营 /',
  '主 编 /',
  '⭐星标⭐',
  '我特意做了教程',
  '每一个「在看」我都当成喜欢',
  'end.',
  'p.s.',
];
const List<String> _wechatLeadingNoisePhrases = [
  '预约直播',
  '活出自己',
  '点击上方',
  '点击下方',
  '👇',
];

void _promoteWechatLazyImageSources(dom.DocumentFragment fragment) {
  for (final image in fragment.querySelectorAll('img')) {
    final resolved = _resolveWechatImageSource(image);
    if (resolved != null) {
      image.attributes['src'] = resolved;
    }
    for (final attribute in _wechatLazyImageAttributes) {
      image.attributes.remove(attribute);
    }
  }
}

String? _resolveWechatImageSource(dom.Element image) {
  final candidates = <String?>[
    image.attributes['data-src'],
    image.attributes['data-lazy-src'],
    image.attributes['data-actualsrc'],
    image.attributes['data-original'],
    image.attributes['src'],
  ];
  String? fallback;
  for (final value in candidates) {
    final normalized = normalizeShareText(value);
    if (normalized == null) continue;
    final sanitized = _sanitizeWechatImageUrl(normalized);
    fallback ??= sanitized;
    if (!normalized.toLowerCase().startsWith('data:')) {
      return sanitized;
    }
  }
  return fallback;
}

String _sanitizeWechatImageUrl(String raw) {
  var sanitized = _decodeWechatHtmlEntities(raw.trim());
  sanitized = sanitized.replaceAll(
    RegExp(r'#imgIndex=\d+.*$', caseSensitive: false),
    '',
  );
  for (final marker in const ['<', '>', '"', "'", ' ']) {
    final index = sanitized.indexOf(marker);
    if (index > 0) {
      sanitized = sanitized.substring(0, index);
    }
  }
  final uri = Uri.tryParse(sanitized);
  if (uri != null && uri.fragment.toLowerCase().startsWith('imgindex=')) {
    sanitized = uri.replace(fragment: '').toString();
  }
  final reparsed = Uri.tryParse(sanitized);
  if (reparsed != null &&
      reparsed.scheme.toLowerCase() == 'http' &&
      reparsed.host.toLowerCase().endsWith('qpic.cn')) {
    sanitized = reparsed.replace(scheme: 'https').toString();
  }
  return sanitized.replaceAll(
    RegExp(r'#imgIndex=\d+$', caseSensitive: false),
    '',
  );
}

String _decodeWechatHtmlEntities(String value) {
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

void _removeBrokenWechatImageTextTails(dom.Node root) {
  for (final child in root.nodes.toList(growable: false)) {
    _removeBrokenWechatImageTextTails(child);
  }

  if (root is! dom.Text) return;
  final original = root.text;
  final cleaned = original.replaceAll(_wechatBrokenImageTailPattern, '');
  if (cleaned == original) return;
  if (_normalizeText(cleaned) == null) {
    root.remove();
    return;
  }
  root.text = cleaned;
}

void _removeKnownWechatNoise(dom.DocumentFragment fragment) {
  for (final selector in _wechatNoiseSelectors) {
    for (final element
        in fragment.querySelectorAll(selector).toList(growable: false)) {
      element.remove();
    }
  }

  for (final element
      in fragment.querySelectorAll('*').toList(growable: false)) {
    final style = (element.attributes['style'] ?? '').toLowerCase();
    final ariaHidden = (element.attributes['aria-hidden'] ?? '').toLowerCase();
    if (style.contains('display:none') ||
        style.contains('visibility:hidden') ||
        ariaHidden == 'true') {
      element.remove();
    }
  }
}

void _unwrapRedundantInlineTags(dom.Node root) {
  for (final child in root.nodes.toList(growable: false)) {
    _unwrapRedundantInlineTags(child);
  }

  if (root is! dom.Element) return;
  final tag = root.localName?.toLowerCase();
  if (tag == null || !_inlineTagsToUnwrap.contains(tag)) return;
  if (root.attributes.isNotEmpty) return;

  final replacement = dom.DocumentFragment();
  root.reparentChildren(replacement);
  root.replaceWith(replacement);
}

void _trimWechatLeadingNoise(dom.DocumentFragment fragment) {
  final parent = _effectiveTrimParent(fragment);
  final nodes = parent.nodes.toList(growable: false);
  for (final node in nodes) {
    if (!_shouldTrimLeadingNode(node)) break;
    node.remove();
  }
}

void _trimWechatTrailingNoise(dom.DocumentFragment fragment) {
  final parent = _effectiveTrimParent(fragment);
  final nodes = parent.nodes
      .where(_containsMeaningfulContent)
      .toList(growable: false);
  if (nodes.isEmpty) return;

  for (var index = 0; index < nodes.length; index++) {
    final text = _normalizedNodeText(nodes[index]);
    if (_shouldHardStopAt(text)) {
      for (
        var removalIndex = index;
        removalIndex < nodes.length;
        removalIndex++
      ) {
        nodes[removalIndex].remove();
      }
      return;
    }
  }

  for (var index = nodes.length - 1; index >= 0; index--) {
    if (!_shouldTrimTrailingNode(nodes[index])) break;
    nodes[index].remove();
  }
}

dom.Node _effectiveTrimParent(dom.DocumentFragment fragment) {
  dom.Node current = fragment;
  while (current.nodes.length == 1) {
    final child = current.nodes.first;
    if (child is! dom.Element) break;
    final tag = child.localName?.toLowerCase();
    if (tag != 'div' && tag != 'section' && tag != 'article') break;
    current = child;
  }
  return current;
}

bool _shouldTrimLeadingNode(dom.Node node) {
  final text = _normalizedNodeText(node);
  if (text.isEmpty) {
    return _isMostlyDecorativeMedia(node);
  }
  if (text.length > 72) return false;
  return _wechatLeadingNoisePhrases.any(text.contains) ||
      (_containsPromoKeyword(text) && text.contains('👇'));
}

bool _shouldTrimTrailingNode(dom.Node node) {
  final text = _normalizedNodeText(node);
  if (text.isEmpty) {
    return _isMostlyDecorativeMedia(node);
  }
  if (_shouldHardStopAt(text)) return true;
  if (text.length > 120) return false;
  return _containsPromoKeyword(text);
}

bool _shouldHardStopAt(String text) {
  if (text.isEmpty) return false;
  return _wechatHardStopPhrases.any(text.contains) ||
      (text.contains('在看') && text.contains('分享')) ||
      (text.contains('作者') && text.contains('主编'));
}

bool _containsPromoKeyword(String text) {
  var matches = 0;
  for (final keyword in _wechatPromoKeywords) {
    if (text.contains(keyword)) {
      matches++;
      if (matches >= 2) return true;
    }
  }
  return false;
}

bool _containsMeaningfulContent(dom.Node node) {
  if (_normalizedNodeText(node).isNotEmpty) return true;
  return node is dom.Element && node.querySelector('img') != null;
}

bool _isMostlyDecorativeMedia(dom.Node node) {
  if (node is! dom.Element) return false;
  final text = _normalizedNodeText(
    node,
  ).replaceAll('👇', '').replaceAll('↑', '').replaceAll('↓', '').trim();
  return text.isEmpty && node.querySelector('img') != null;
}

void _removeEmptyElements(dom.Node root) {
  for (final child in root.nodes.toList(growable: false)) {
    _removeEmptyElements(child);
  }

  if (root is! dom.Element) return;
  final tag = root.localName?.toLowerCase();
  if (tag == null || _voidOrMediaTags.contains(tag)) return;
  if (root.querySelector('img') != null) return;
  if (_normalizedNodeText(root).isEmpty) {
    root.remove();
  }
}

String? _resolveExcerpt(String? cleanedText, String? fallbackExcerpt) {
  final excerpt = normalizeShareText(fallbackExcerpt);
  if (excerpt != null) return excerpt;
  if (cleanedText == null) return null;
  if (cleanedText.length <= 140) return cleanedText;
  return '${cleanedText.substring(0, 140).trimRight()}...';
}

String _normalizedNodeText(dom.Node node) => _normalizeText(node.text) ?? '';

String _serializeNodeHtml(dom.Node node) {
  if (node is dom.Element) return node.outerHtml;
  if (node is dom.DocumentFragment) return node.outerHtml;
  return node.text ?? '';
}

String? _normalizeText(String? value) {
  if (value == null) return null;
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized.isEmpty ? null : normalized;
}
