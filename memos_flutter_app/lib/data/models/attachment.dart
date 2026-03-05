class Attachment {
  const Attachment({
    required this.name,
    required this.filename,
    required this.type,
    required this.size,
    required this.externalLink,
    this.width,
    this.height,
    this.hash,
  });

  final String name;
  final String filename;
  final String type;
  final int size;
  final String externalLink;
  final int? width;
  final int? height;
  final String? hash;

  String get uid {
    if (name.startsWith('attachments/')) return name.substring('attachments/'.length);
    if (name.startsWith('resources/')) return name.substring('resources/'.length);
    return name;
  }

  factory Attachment.fromJson(Map<String, dynamic> json) {
    int? readOptionalInt(String key) {
      final raw = _toInt(json[key]);
      return raw > 0 ? raw : null;
    }

    String? readOptionalString(String key) {
      final raw = json[key];
      if (raw is String) {
        final trimmed = raw.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      return null;
    }

    return Attachment(
      name: (json['name'] as String?) ?? '',
      filename: (json['filename'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
      size: _toInt(json['size']),
      externalLink: (json['externalLink'] as String?) ?? '',
      width: readOptionalInt('width'),
      height: readOptionalInt('height'),
      hash: readOptionalString('hash'),
    );
  }

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{
      'name': name,
      'filename': filename,
      'type': type,
      'size': size,
      'externalLink': externalLink,
    };
    if (width != null) payload['width'] = width;
    if (height != null) payload['height'] = height;
    if (hash != null) payload['hash'] = hash;
    return payload;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
