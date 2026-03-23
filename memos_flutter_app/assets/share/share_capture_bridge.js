function memoflowCapture() {
  const normalize = (value) => {
    if (typeof value !== 'string') {
      return null;
    }
    const normalized = value.replace(/\s+/g, ' ').trim();
    return normalized.length > 0 ? normalized : null;
  };

  const readMeta = (selectors) => {
    for (const selector of selectors) {
      const element = document.querySelector(selector);
      const content = normalize(element && element.getAttribute('content'));
      if (content) {
        return content;
      }
    }
    return null;
  };

  const toAbsoluteUrl = (value) => {
    const normalized = normalize(value);
    if (!normalized) {
      return null;
    }
    try {
      return new URL(normalized, location.href).toString();
    } catch (_) {
      return normalized;
    }
  };

  const collectJsonScripts = () => {
    const blocks = [];
    for (const element of document.querySelectorAll('script[type="application/ld+json"]')) {
      const content = normalize(element.textContent || '');
      if (!content) continue;
      try {
        blocks.push(JSON.parse(content));
      } catch (_) {}
    }
    return blocks;
  };

  const collectBootstrapStates = () => {
    const keys = [
      '__playinfo__',
      '__INITIAL_STATE__',
      '__INITIAL_SSR_STATE__',
    ];
    const result = {};
    for (const key of keys) {
      try {
        const value = window[key];
        if (value !== undefined && value !== null) {
          result[key] = value;
        }
      } catch (_) {}
    }

    const extra = [];
    for (const element of document.querySelectorAll('script')) {
      const content = element.textContent || '';
      if (!content) continue;
      if (content.includes('INITIAL_STATE') || content.includes('note') || content.includes('playurl')) {
        extra.push(content.slice(0, 12000));
      }
    }
    return { windowStates: result, bootstrapStates: extra };
  };

  const rawVideoHints = [];
  const pushVideoHint = (hint) => {
    if (!hint || !hint.url) return;
    rawVideoHints.push(hint);
  };

  const classifyVideoUrl = (url) => {
    if (!url) return { direct: false, unsupported: false };
    const lower = url.toLowerCase();
    if (lower.startsWith('blob:') || lower.startsWith('data:')) {
      return { direct: false, unsupported: true };
    }
    if (lower.includes('.m3u8') || lower.includes('.m3u') || lower.includes('.mpd')) {
      return { direct: false, unsupported: true };
    }
    if (
      lower.includes('.mp4') ||
      lower.includes('.webm') ||
      lower.includes('.mov') ||
      lower.includes('.m4v') ||
      lower.includes('.mkv') ||
      lower.includes('.avi')
    ) {
      return { direct: true, unsupported: false };
    }
    return { direct: false, unsupported: false };
  };

  const collectVideoHints = () => {
    const metaSelectors = [
      'meta[property="og:video"]',
      'meta[property="og:video:url"]',
      'meta[property="og:video:secure_url"]',
      'meta[name="twitter:player:stream"]',
    ];
    for (const selector of metaSelectors) {
      const element = document.querySelector(selector);
      const url = toAbsoluteUrl(element && element.getAttribute('content'));
      if (!url) continue;
      const status = classifyVideoUrl(url);
      pushVideoHint({
        url,
        source: 'meta',
        mimeType: null,
        isDirectDownloadable: status.direct,
        reason: status.unsupported ? 'stream_only_not_supported' : null,
      });
    }

    for (const element of document.querySelectorAll('video')) {
      const directUrl = toAbsoluteUrl(element.getAttribute('src'));
      if (directUrl) {
        const status = classifyVideoUrl(directUrl);
        pushVideoHint({
          url: directUrl,
          source: 'dom',
          mimeType: element.getAttribute('type') || null,
          title: normalize(element.getAttribute('title')),
          isDirectDownloadable: status.direct,
          reason: status.unsupported ? 'stream_only_not_supported' : null,
        });
      }
      for (const source of element.querySelectorAll('source')) {
        const sourceUrl = toAbsoluteUrl(source.getAttribute('src'));
        if (!sourceUrl) continue;
        const status = classifyVideoUrl(sourceUrl);
        pushVideoHint({
          url: sourceUrl,
          source: 'dom',
          mimeType: source.getAttribute('type') || null,
          title: normalize(element.getAttribute('title')),
          isDirectDownloadable: status.direct,
          reason: status.unsupported ? 'stream_only_not_supported' : null,
        });
      }
    }

    for (const element of document.querySelectorAll('link[rel="preload"][as="video"]')) {
      const url = toAbsoluteUrl(element.getAttribute('href'));
      if (!url) continue;
      const status = classifyVideoUrl(url);
      pushVideoHint({
        url,
        source: 'link',
        mimeType: element.getAttribute('type') || null,
        isDirectDownloadable: status.direct,
        reason: status.unsupported ? 'stream_only_not_supported' : null,
      });
    }

    for (const element of document.querySelectorAll('a[href]')) {
      const href = toAbsoluteUrl(element.getAttribute('href'));
      if (!href) continue;
      const status = classifyVideoUrl(href);
      if (!status.direct && !status.unsupported) continue;
      pushVideoHint({
        url: href,
        source: 'link',
        title: normalize(element.textContent || ''),
        isDirectDownloadable: status.direct,
        reason: status.unsupported ? 'stream_only_not_supported' : null,
      });
    }

    for (const block of collectJsonScripts()) {
      const nodes = Array.isArray(block) ? block : [block];
      for (const node of nodes) {
        if (!node || typeof node !== 'object') continue;
        const typeValue = String(node['@type'] || node.type || '').toLowerCase();
        if (!typeValue.includes('videoobject')) continue;
        const url = toAbsoluteUrl(node.contentUrl || node.embedUrl || node.url);
        if (!url) continue;
        const status = classifyVideoUrl(url);
        pushVideoHint({
          url,
          source: 'jsonld',
          title: normalize(node.name || node.headline || ''),
          isDirectDownloadable: status.direct,
          reason: status.unsupported ? 'stream_only_not_supported' : null,
        });
      }
    }
  };

  const fallbackText = () => {
    const root = document.body || document.documentElement;
    return normalize(root && root.innerText ? root.innerText : '');
  };

  const ogTitle = readMeta([
    'meta[property="og:title"]',
    'meta[name="og:title"]',
    'meta[name="twitter:title"]'
  ]);
  const siteName = readMeta([
    'meta[property="og:site_name"]',
    'meta[name="application-name"]'
  ]);
  const description = readMeta([
    'meta[name="description"]',
    'meta[property="og:description"]',
    'meta[name="twitter:description"]'
  ]);
  const leadImageUrl = readMeta([
    'meta[property="og:image"]',
    'meta[name="twitter:image"]'
  ]);

  let parsed = null;
  let error = null;
  try {
    const clonedDocument = document.cloneNode(true);
    parsed = new Readability(clonedDocument).parse();
  } catch (captureError) {
    error = String(
      captureError && captureError.message ? captureError.message : captureError
    );
  }

  collectVideoHints();
  const bootstrap = collectBootstrapStates();
  const structuredData = collectJsonScripts();
  const parsedText = normalize(parsed && parsed.textContent ? parsed.textContent : null);
  const textContent = parsedText || fallbackText();
  const contentHtml =
    parsed && typeof parsed.content === 'string' && parsed.content.trim().length > 0
      ? parsed.content
      : null;

  return {
    finalUrl: String(location && location.href ? location.href : ''),
    pageTitle: normalize(document.title),
    articleTitle: normalize(parsed && parsed.title ? parsed.title : ogTitle),
    siteName: normalize(parsed && parsed.siteName ? parsed.siteName : siteName),
    byline: normalize(parsed && parsed.byline ? parsed.byline : null),
    excerpt: normalize(parsed && parsed.excerpt ? parsed.excerpt : description),
    contentHtml: contentHtml,
    textContent: textContent,
    leadImageUrl: normalize(leadImageUrl),
    length: textContent ? textContent.length : 0,
    readabilitySucceeded: !!contentHtml,
    rawVideoHints: rawVideoHints,
    structuredData: structuredData,
    windowStates: bootstrap.windowStates,
    bootstrapStates: bootstrap.bootstrapStates,
    pageUserAgent: normalize(navigator.userAgent),
    error: error,
  };
}
