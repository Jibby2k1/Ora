class ExerciseScienceInfo {
  const ExerciseScienceInfo({
    required this.exerciseId,
    required this.instructions,
    required this.avoid,
    required this.citations,
    required this.visualAssetPaths,
    this.sections = const [],
    this.sourceDocuments = const [],
  });

  final int exerciseId;
  final List<String> instructions;
  final List<String> avoid;
  final List<String> citations;
  final List<String> visualAssetPaths;
  final List<ExerciseScienceSection> sections;
  final List<ExerciseScienceSourceDocument> sourceDocuments;

  List<ExerciseScienceSection> get orderedSections {
    final items = sections.where((section) => section.hasContent).toList();
    items.sort((a, b) {
      final aPriority = _sectionPriority[a.normalizedId] ?? 100;
      final bPriority = _sectionPriority[b.normalizedId] ?? 100;
      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return items;
  }

  ExerciseScienceSection? sectionForKey(String key) {
    final normalized = _normalizeScienceKey(key);
    for (final section in sections) {
      if (section.normalizedId == normalized) {
        return section;
      }
    }
    return null;
  }

  List<ExerciseScienceSourceDocument> get resolvedSourceDocuments {
    if (sourceDocuments.isNotEmpty) {
      return sourceDocuments;
    }
    return ExerciseScienceSourceDocument.listFromDynamic(
      citations,
      fallbackCitations: citations,
    );
  }

  ExerciseScienceSourceDocument? sourceById(String sourceId) {
    final normalized = _normalizeSourceReference(sourceId);
    for (final document in resolvedSourceDocuments) {
      if (document.normalizedId == normalized) {
        return document;
      }
    }
    return null;
  }
}

class ExerciseScienceSection {
  const ExerciseScienceSection({
    required this.id,
    required this.title,
    this.summary,
    this.items = const [],
  });

  final String id;
  final String title;
  final String? summary;
  final List<ExerciseSciencePoint> items;

  String get normalizedId => _normalizeScienceKey(id);

  bool get hasContent {
    final summaryText = summary?.trim();
    return (summaryText != null && summaryText.isNotEmpty) || items.isNotEmpty;
  }

  Map<String, Object?> toJson() {
    return {
      'id': normalizedId,
      'title': title,
      if (summary != null && summary!.trim().isNotEmpty) 'summary': summary,
      'items': [for (final item in items) item.toJson()],
    };
  }

  static List<ExerciseScienceSection> listFromDynamic(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    final sections = <ExerciseScienceSection>[];
    for (final item in raw) {
      final section = fromDynamic(item);
      if (section != null && section.hasContent) {
        sections.add(section);
      }
    }
    return sections;
  }

  static ExerciseScienceSection? fromDynamic(dynamic raw) {
    final map = _asStringKeyMap(raw);
    if (map == null) {
      return null;
    }
    final rawId = _firstNonEmptyString(map, ['id', 'key', 'slug']);
    final rawTitle = _firstNonEmptyString(map, ['title', 'label']);
    final id = _normalizeScienceKey(rawId ?? rawTitle ?? '');
    if (id.isEmpty) {
      return null;
    }
    final title = rawTitle ?? _titleFromKey(id);
    final summary = _firstNonEmptyString(
      map,
      ['summary', 'overview', 'description'],
    );
    final items = ExerciseSciencePoint.listFromDynamic(
      map['items'] ?? map['claims'] ?? map['points'],
    );
    return ExerciseScienceSection(
      id: id,
      title: title,
      summary: summary,
      items: items,
    );
  }
}

class ExerciseSciencePoint {
  const ExerciseSciencePoint({
    required this.title,
    this.detail,
    this.sourceIds = const [],
  });

  final String title;
  final String? detail;
  final List<String> sourceIds;

  Map<String, Object?> toJson() {
    return {
      'title': title,
      if (detail != null && detail!.trim().isNotEmpty) 'detail': detail,
      'source_ids': sourceIds,
    };
  }

  static List<ExerciseSciencePoint> listFromDynamic(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    final points = <ExerciseSciencePoint>[];
    for (final item in raw) {
      final point = fromDynamic(item);
      if (point != null) {
        points.add(point);
      }
    }
    return points;
  }

  static ExerciseSciencePoint? fromDynamic(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      final value = raw.trim();
      if (value.isEmpty) {
        return null;
      }
      return ExerciseSciencePoint(title: value);
    }
    final map = _asStringKeyMap(raw);
    if (map == null) {
      final value = raw.toString().trim();
      if (value.isEmpty) {
        return null;
      }
      return ExerciseSciencePoint(title: value);
    }

    final title = _firstNonEmptyString(
      map,
      ['title', 'claim', 'text', 'label', 'summary'],
    );
    final detail = _firstNonEmptyString(
      map,
      ['detail', 'body', 'note', 'description', 'explanation'],
    );
    final normalizedTitle = title?.trim();
    final normalizedDetail = detail?.trim();
    if ((normalizedTitle == null || normalizedTitle.isEmpty) &&
        (normalizedDetail == null || normalizedDetail.isEmpty)) {
      return null;
    }

    return ExerciseSciencePoint(
      title: normalizedTitle?.isNotEmpty == true
          ? normalizedTitle!
          : normalizedDetail!,
      detail: normalizedTitle?.isNotEmpty == true &&
              normalizedDetail != null &&
              normalizedDetail.isNotEmpty
          ? normalizedDetail
          : null,
      sourceIds: _normalizeSourceIds(
        map['source_ids'] ?? map['sources'] ?? map['document_ids'],
      ),
    );
  }
}

class ExerciseScienceSourceDocument {
  const ExerciseScienceSourceDocument({
    required this.id,
    required this.citation,
    this.title,
    this.documentType,
    this.url,
    this.year,
    this.relevance,
  });

  final String id;
  final String citation;
  final String? title;
  final String? documentType;
  final String? url;
  final int? year;
  final String? relevance;

  String get normalizedId => _normalizeSourceReference(id);

  String get displayTitle {
    final normalizedTitle = title?.trim();
    if (normalizedTitle != null && normalizedTitle.isNotEmpty) {
      return normalizedTitle;
    }
    return citation;
  }

  Map<String, Object?> toJson() {
    return {
      'id': normalizedId,
      if (title != null && title!.trim().isNotEmpty) 'title': title,
      'citation': citation,
      if (documentType != null && documentType!.trim().isNotEmpty)
        'document_type': documentType,
      if (url != null && url!.trim().isNotEmpty) 'url': url,
      if (year != null) 'year': year,
      if (relevance != null && relevance!.trim().isNotEmpty)
        'relevance': relevance,
    };
  }

  static List<ExerciseScienceSourceDocument> listFromDynamic(
    dynamic raw, {
    List<String> fallbackCitations = const [],
  }) {
    final documents = <ExerciseScienceSourceDocument>[];
    if (raw is List) {
      for (final item in raw) {
        final document = fromDynamic(item, fallbackIndex: documents.length + 1);
        if (document != null) {
          documents.add(document);
        }
      }
    }

    if (documents.isEmpty && fallbackCitations.isNotEmpty) {
      for (final citation in fallbackCitations) {
        final normalizedCitation = citation.trim();
        if (normalizedCitation.isEmpty) {
          continue;
        }
        documents.add(
          ExerciseScienceSourceDocument(
            id: 'S${documents.length + 1}',
            citation: normalizedCitation,
          ),
        );
      }
    }

    final normalizedDocuments = <ExerciseScienceSourceDocument>[];
    final usedIds = <String>{};
    for (final document in documents) {
      var id = document.normalizedId;
      if (id.isEmpty || usedIds.contains(id)) {
        id = 'S${normalizedDocuments.length + 1}';
      }
      usedIds.add(id);
      normalizedDocuments.add(
        ExerciseScienceSourceDocument(
          id: id,
          citation: document.citation,
          title: document.title,
          documentType: document.documentType,
          url: document.url,
          year: document.year,
          relevance: document.relevance,
        ),
      );
    }
    return normalizedDocuments;
  }

  static ExerciseScienceSourceDocument? fromDynamic(
    dynamic raw, {
    required int fallbackIndex,
  }) {
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      final citation = raw.trim();
      if (citation.isEmpty) {
        return null;
      }
      return ExerciseScienceSourceDocument(
        id: 'S$fallbackIndex',
        citation: citation,
      );
    }

    final map = _asStringKeyMap(raw);
    if (map == null) {
      final citation = raw.toString().trim();
      if (citation.isEmpty) {
        return null;
      }
      return ExerciseScienceSourceDocument(
        id: 'S$fallbackIndex',
        citation: citation,
      );
    }

    final citation = _firstNonEmptyString(
      map,
      ['citation', 'reference', 'text', 'source'],
    );
    final title = _firstNonEmptyString(map, ['title']);
    final resolvedCitation = citation ?? title;
    if (resolvedCitation == null || resolvedCitation.trim().isEmpty) {
      return null;
    }

    return ExerciseScienceSourceDocument(
      id: _normalizeSourceReference(
        _firstNonEmptyString(map, ['id', 'source_id', 'document_id', 'ref']) ??
            'S$fallbackIndex',
      ),
      citation: resolvedCitation.trim(),
      title: title,
      documentType:
          _firstNonEmptyString(map, ['document_type', 'type', 'kind']),
      url: _firstNonEmptyString(map, ['url', 'link', 'doi_url']),
      year: _firstInt(map, ['year']),
      relevance: _firstNonEmptyString(
        map,
        ['relevance', 'note', 'summary', 'why_it_matters'],
      ),
    );
  }
}

const Map<String, int> _sectionPriority = {
  'safety': 0,
  'effectiveness': 1,
  'programming': 2,
  'considerations': 3,
};

Map<String, dynamic>? _asStringKeyMap(dynamic raw) {
  if (raw is! Map) {
    return null;
  }
  final map = <String, dynamic>{};
  raw.forEach((key, value) {
    map[key.toString()] = value;
  });
  return map;
}

String? _firstNonEmptyString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) {
      continue;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
  }
  return null;
}

int? _firstInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value == null) {
      continue;
    }
    final parsed = int.tryParse(value.toString().trim());
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}

List<String> _normalizeSourceIds(dynamic raw) {
  final values = <String>[];
  if (raw is List) {
    for (final item in raw) {
      final text = _normalizeSourceReference(item.toString());
      if (text.isNotEmpty && !values.contains(text)) {
        values.add(text);
      }
    }
    return values;
  }
  if (raw == null) {
    return const [];
  }
  final text = _normalizeSourceReference(raw.toString());
  if (text.isEmpty) {
    return const [];
  }
  return [text];
}

String _normalizeScienceKey(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return normalized;
}

String _normalizeSourceReference(String value) {
  return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}

String _titleFromKey(String key) {
  final normalized = _normalizeScienceKey(key);
  if (normalized.isEmpty) {
    return 'Information';
  }
  return normalized
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
