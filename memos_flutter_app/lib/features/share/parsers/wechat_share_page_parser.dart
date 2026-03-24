import '../share_clip_models.dart';
import 'share_page_parser.dart';
import 'wechat_article_content_cleaner.dart';

class WechatSharePageParser implements SharePageParser {
  @override
  bool canParse(SharePageSnapshot snapshot) {
    final host = snapshot.host.toLowerCase();
    return host == 'mp.weixin.qq.com' || host.endsWith('.mp.weixin.qq.com');
  }

  @override
  SharePageParserResult parse(SharePageSnapshot snapshot) {
    final bridge = snapshot.bridgeData;
    final cleaned = cleanWechatArticleContent(
      rawHtml: bridge['contentHtml']?.toString(),
      fallbackTextContent: bridge['textContent']?.toString(),
      fallbackExcerpt: bridge['excerpt']?.toString(),
    );

    final contentHtml = normalizeShareText(cleaned.contentHtml);
    final textContent = normalizeShareText(cleaned.textContent);
    final pageKind =
        ((contentHtml ?? '').isNotEmpty || (textContent ?? '').length >= 80)
        ? SharePageKind.article
        : SharePageKind.unknown;

    return SharePageParserResult(
      pageKind: pageKind,
      title:
          normalizeShareText(bridge['articleTitle']?.toString()) ??
          normalizeShareText(bridge['pageTitle']?.toString()),
      excerpt: normalizeShareText(cleaned.excerpt),
      contentHtml: contentHtml,
      textContent: textContent,
      siteName: normalizeShareText(bridge['siteName']?.toString()) ?? '微信公众平台',
      byline: normalizeShareText(bridge['byline']?.toString()),
      leadImageUrl: normalizeShareText(bridge['leadImageUrl']?.toString()),
      parserTag: 'wechat',
    );
  }
}
