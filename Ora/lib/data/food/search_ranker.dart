import 'dart:math';

import '../../domain/models/food_models.dart';

class FoodSearchRanker {
  const FoodSearchRanker({
    this.stopWords = const {'a', 'an', 'and', 'the', 'of'},
  });

  final Set<String> stopWords;

  List<FoodSearchResult> rankResults({
    required List<FoodSearchResult> input,
    required String query,
    required FoodSearchCategory category,
    required Set<String> recentNames,
    bool includeAllTokensBoost = true,
  }) {
    final tokens = tokenizeForScoring(query);
    final deduped = <String, _ScoredResult>{};

    for (final item in input) {
      final score = scoreResult(
        item,
        query: query,
        queryTokens: tokens,
        category: category,
        recentNames: recentNames,
        includeAllTokensBoost: includeAllTokensBoost,
      );
      final key = '${_normalizeText(item.name)}|${_normalizeText(item.brand ?? "")}';
      final previous = deduped[key];
      if (previous == null || score > previous.score) {
        deduped[key] = _ScoredResult(item: item, score: score);
      }
    }

    final ranked = deduped.values.toList(growable: false)
      ..sort((left, right) {
        final byScore = right.score.compareTo(left.score);
        if (byScore != 0) return byScore;
        return left.item.name.compareTo(right.item.name);
      });
    return ranked.map((entry) => entry.item).toList(growable: false);
  }

  double scoreResult(
    FoodSearchResult result, {
    required String query,
    required List<String> queryTokens,
    required FoodSearchCategory category,
    required Set<String> recentNames,
    bool includeAllTokensBoost = true,
  }) {
    var score = 0.0;
    final name = _normalizeText(result.name);
    final dataType = _normalizeText(result.dataType ?? '');
    final queryNormalized = _normalizeText(query);

    if (name == queryNormalized) {
      score += 120;
    } else if (name.startsWith(queryNormalized)) {
      score += 70;
    }

    final candidateTokens = tokenizeForScoring(name);
    final coverage = _coverageScore(queryTokens, candidateTokens, name);
    score += coverage * 80;

    if (includeAllTokensBoost && _containsAllTokens(queryTokens, candidateTokens, name)) {
      score += 25;
    }

    final similarity = _querySimilarity(queryNormalized, name);
    score += similarity * 60;

    if (recentNames.contains(name)) {
      score += 20;
    }

    if (result.source == FoodSource.custom) {
      score += 40;
    }

    score += _sourceBoost(result, category, dataType: dataType);

    if (result.hasRichNutrientPanel) {
      score += 8;
    }

    return score;
  }

  String buildRequiredTokenQuery(String query) {
    final pieces = RegExp(r'"([^"]+)"|(\S+)').allMatches(query);
    final transformed = <String>[];
    for (final match in pieces) {
      final quoted = match.group(1);
      final raw = (quoted ?? match.group(2) ?? '').trim();
      if (raw.isEmpty) continue;
      final normalized = quoted == null
          ? _normalizeText(raw)
          : raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (quoted == null && stopWords.contains(normalized)) continue;
      transformed.add(quoted == null ? '+$normalized' : '"$normalized"');
    }
    return transformed.join(' ');
  }

  List<String> tokenizeForScoring(String query) {
    final matches = RegExp(r'"([^"]+)"|(\S+)').allMatches(query);
    final tokens = <String>[];
    for (final match in matches) {
      final quoted = match.group(1);
      final raw = (quoted ?? match.group(2) ?? '').trim();
      if (raw.isEmpty) continue;
      final token = quoted == null
          ? _normalizeText(raw)
          : raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (quoted == null && stopWords.contains(token)) continue;
      if (token.isNotEmpty) {
        tokens.add(token);
      }
    }
    return tokens;
  }

  bool _containsAllTokens(
    List<String> queryTokens,
    List<String> candidateTokens,
    String candidateName,
  ) {
    if (queryTokens.isEmpty) return false;
    return queryTokens.every((token) => _candidateTokenMatch(token, candidateTokens, candidateName));
  }

  double _coverageScore(
    List<String> queryTokens,
    List<String> candidateTokens,
    String candidateName,
  ) {
    if (queryTokens.isEmpty) return 0;
    var matchedTokens = 0;
    for (final token in queryTokens) {
      if (_candidateTokenMatch(token, candidateTokens, candidateName)) {
        matchedTokens++;
      }
    }
    return matchedTokens / max(1, queryTokens.length);
  }

  bool _candidateTokenMatch(
    String token,
    List<String> candidateTokens,
    String candidateName,
  ) {
    if (token.contains(' ')) {
      return candidateName.contains(token);
    }
    for (final candidateToken in candidateTokens) {
      if (candidateToken == token || candidateToken.startsWith(token)) {
        return true;
      }
    }
    return false;
  }

  double _querySimilarity(String query, String candidate) {
    final normalizedQuery = _normalizeText(query);
    final normalizedCandidate = _normalizeText(candidate);
    if (normalizedQuery.isEmpty || normalizedCandidate.isEmpty) return 0;

    final qLen = normalizedQuery.length;
    final cLen = normalizedCandidate.length;

    int bestDistance;
    if (cLen <= qLen + 2) {
      bestDistance = _damerauLevenshtein(
        normalizedQuery,
        normalizedCandidate,
        maxDistance: qLen + 10,
      );
    } else {
      final win = max(4, min(qLen + 2, qLen + 6));
      final upper = max(0, cLen - win);
      final steps = min(30, upper);
      var minimal = qLen + cLen;
      for (var i = 0; i <= steps; i++) {
        final window = normalizedCandidate.substring(i, i + win);
        final distance = _damerauLevenshtein(
          normalizedQuery,
          window,
          maxDistance: minimal,
        );
        if (distance < minimal) {
          minimal = distance;
          if (minimal == 0) {
            break;
          }
        }
      }
      bestDistance = minimal;
    }

    final denominator = max(qLen, 1);
    final similarity = 1 - (bestDistance / denominator);
    if (similarity.isNaN) return 0;
    return similarity.clamp(0.0, 1.0);
  }

  int _damerauLevenshtein(
    String a,
    String b, {
    int maxDistance = 255,
  }) {
    final lenA = a.length;
    final lenB = b.length;

    if ((lenA - lenB).abs() > maxDistance) {
      return maxDistance + 1;
    }
    if (lenA == 0) return lenB;
    if (lenB == 0) return lenA;

    final matrix = List<List<int>>.generate(
      lenA + 1,
      (_) => List<int>.filled(lenB + 1, 0),
    );

    for (var i = 0; i <= lenA; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= lenB; j++) {
      matrix[0][j] = j;
    }

    for (var i = 1; i <= lenA; i++) {
      var rowMin = maxDistance + 1;
      final charA = a.codeUnitAt(i - 1);
      for (var j = 1; j <= lenB; j++) {
        final charB = b.codeUnitAt(j - 1);
        final cost = charA == charB ? 0 : 1;
        final deletion = matrix[i - 1][j] + 1;
        final insertion = matrix[i][j - 1] + 1;
        final substitution = matrix[i - 1][j - 1] + cost;
        var value = min(deletion, min(insertion, substitution));

        if (i > 1 &&
            j > 1 &&
            charA == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == charB) {
          value = min(value, matrix[i - 2][j - 2] + 1);
        }

        matrix[i][j] = value;
        if (value < rowMin) {
          rowMin = value;
        }
      }
      if (rowMin > maxDistance) {
        return maxDistance + 1;
      }
    }

    return matrix[lenA][lenB];
  }

  double _sourceBoost(
    FoodSearchResult result,
    FoodSearchCategory category, {
    required String dataType,
  }) {
    if (result.source == FoodSource.custom) return 40;
    if (result.source == FoodSource.usdaFdc) {
      if (category == FoodSearchCategory.commonFoods ||
          category == FoodSearchCategory.branded) {
        if (dataType == 'foundation') return 25;
        if (dataType == 'sr legacy' || dataType == 'srlegacy' || dataType == 'sr') {
          return 20;
        }
        if (dataType == 'survey' || dataType.contains('fndds')) return 10;
        if (result.isBranded || dataType == 'branded') return 8;
      }
    }
    if (result.source == FoodSource.nutritionix) return 6;
    if (result.source == FoodSource.openFoodFacts) return 0;
    return 0;
  }

  String _normalizeText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _ScoredResult {
  _ScoredResult({
    required this.item,
    required this.score,
  });

  final FoodSearchResult item;
  final double score;
}
