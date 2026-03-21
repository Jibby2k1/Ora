import 'dart:math';

import '../../domain/models/food_models.dart';

class FoodSearchRanker {
  const FoodSearchRanker({
    this.stopWords = const {'a', 'an', 'and', 'the', 'of'},
  });

  final Set<String> stopWords;

  static const Set<String> _genericFoodTerms = {
    'chicken',
    'breast',
    'egg',
    'banana',
    'rice',
    'beef',
    'turkey',
    'salmon',
    'yogurt',
    'milk',
    'oatmeal',
    'potato',
  };

  static const Set<String> _brandHints = {
    'tyson',
    'fairlife',
    'quest',
    'kirkland',
    'chobani',
    'fage',
    'dannon',
    'oscar',
    'mayer',
    'trader',
    'joes',
    'costco',
    'walmart',
    'great',
    'value',
  };

  List<FoodSearchResult> rankResults({
    required List<FoodSearchResult> input,
    required String query,
    required FoodSearchCategory category,
    required Set<String> recentNames,
    Set<String> favoriteNames = const <String>{},
  }) {
    final normalizedQuery = normalizeQuery(query);
    if (normalizedQuery.isEmpty) {
      return input;
    }
    final queryTokens = tokenize(normalizedQuery);
    final genericIntent = _isGenericFoodIntent(
      normalizedQuery: normalizedQuery,
      queryTokens: queryTokens,
    );

    final deduped = <String, _ScoredResult>{};
    for (final item in input) {
      final score = computeScore(
        queryNormalized: normalizedQuery,
        queryTokens: queryTokens,
        result: item,
        category: category,
        recentNames: recentNames,
        favoriteNames: favoriteNames,
        genericIntent: genericIntent,
      );
      final dedupeKey =
          '${normalizeQuery(item.name)}|${normalizeQuery(item.brand ?? '')}';
      final existing = deduped[dedupeKey];
      if (existing == null || score > existing.score) {
        deduped[dedupeKey] = _ScoredResult(item: item, score: score);
      }
    }

    final ranked = deduped.values.toList(growable: false)
      ..sort((left, right) {
        final byScore = right.score.compareTo(left.score);
        if (byScore != 0) return byScore;

        // Stable tie-breaker: generic -> custom -> branded
        final leftPriority = _resultTypePriority(left.item.resultType);
        final rightPriority = _resultTypePriority(right.item.resultType);
        final byType = leftPriority.compareTo(rightPriority);
        if (byType != 0) return byType;

        return left.item.name.compareTo(right.item.name);
      });

    return ranked.map((entry) => entry.item).toList(growable: false);
  }

  String normalizeQuery(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u0000-\u001f]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> tokenize(String normalizedQuery) {
    return normalizedQuery
        .split(' ')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && !stopWords.contains(value))
        .toList(growable: false);
  }

  String buildRequiredTokenQuery(String query) {
    final normalized = normalizeQuery(query);
    if (normalized.isEmpty) return '';
    final tokens = tokenize(normalized);
    if (tokens.isEmpty) return normalized;
    return tokens.map((token) => '+$token').join(' ');
  }

  double computeScore({
    required String queryNormalized,
    required List<String> queryTokens,
    required FoodSearchResult result,
    required FoodSearchCategory category,
    required Set<String> recentNames,
    required Set<String> favoriteNames,
    required bool genericIntent,
  }) {
    final candidateName = normalizeQuery(result.name);
    if (candidateName.isEmpty) {
      return -10000;
    }

    final candidateTokens = tokenize(candidateName);
    final phraseMatch = candidateName.contains(queryNormalized);
    final exactMatch = candidateName == queryNormalized;
    final prefixMatch = candidateName.startsWith(queryNormalized);
    final matchedTokens = _countMatchedTokens(
      queryTokens: queryTokens,
      candidateTokens: candidateTokens,
      candidateName: candidateName,
    );
    final allTokensPresent =
        queryTokens.isNotEmpty && matchedTokens == queryTokens.length;
    final missingTokens = max(0, queryTokens.length - matchedTokens);
    final tokenCoverage =
        queryTokens.isEmpty ? 0.0 : matchedTokens / max(1, queryTokens.length);

    final inOrder = _tokensInOrder(
      queryTokens: queryTokens,
      candidateName: candidateName,
    );
    final adjacent = _tokensAdjacent(
      queryTokens: queryTokens,
      candidateName: candidateName,
    );

    var score = 0.0;

    if (phraseMatch) score += 120;
    if (exactMatch) score += 120;
    if (prefixMatch) score += 80;

    if (allTokensPresent) {
      score += 60;
    } else {
      // Hard gate: missing tokens are strongly penalized.
      score -= missingTokens * 110;
      if (matchedTokens == 0 && queryTokens.isNotEmpty) {
        score -= 220;
      }
    }

    score += tokenCoverage * 80;

    if (inOrder) score += 30;
    if (adjacent) score += 20;

    final shouldRunFuzzy =
        phraseMatch || matchedTokens > 0 || queryTokens.length <= 1;
    if (shouldRunFuzzy) {
      final fuzzySimilarity = substringEditDistanceScore(
        queryNormalized: queryNormalized,
        candidateNormalized: candidateName,
      );
      score += fuzzySimilarity * 60;
    } else {
      score -= 40;
    }

    if (recentNames.contains(candidateName)) {
      score += 35;
    }
    if (favoriteNames.contains(candidateName)) {
      score += 25;
    }
    if (result.hasRichNutrientPanel) {
      score += 8;
    }
    final normalizedDataType = (result.dataType ?? '').toLowerCase().trim();
    if (result.source == FoodSource.usdaFdc) {
      if (normalizedDataType.contains('foundation')) {
        score += 35;
      } else if (normalizedDataType.contains('sr legacy')) {
        score += 30;
      } else if (normalizedDataType.contains('survey') ||
          normalizedDataType.contains('fndds')) {
        score += 14;
      } else if (normalizedDataType.contains('branded')) {
        score += 8;
      } else {
        score += 12;
      }

      if (category == FoodSearchCategory.commonFoods &&
          !normalizedDataType.contains('branded')) {
        score += 20;
      }
      if (category == FoodSearchCategory.all &&
          genericIntent &&
          result.resultType == FoodResultType.generic) {
        score += 20;
      }
    }
    if (queryTokens.contains('raw') && candidateName.contains('raw')) {
      score += 28;
    }
    if (queryTokens.contains('cooked') && candidateName.contains('cooked')) {
      score += 20;
    }

    final explicitBrandHit = _isExplicitBrandHit(
      queryNormalized: queryNormalized,
      result: result,
    );
    final brandedIntent = _isBrandedIntent(
      queryNormalized: queryNormalized,
      queryTokens: queryTokens,
    );

    switch (result.resultType) {
      case FoodResultType.generic:
        if (genericIntent || category == FoodSearchCategory.commonFoods) {
          score += 20;
        } else {
          score += 8;
        }
        break;
      case FoodResultType.custom:
        score += 20;
        if (category == FoodSearchCategory.custom) {
          score += 20;
        }
        break;
      case FoodResultType.branded:
        if ((genericIntent || category == FoodSearchCategory.commonFoods) &&
            !explicitBrandHit &&
            !brandedIntent) {
          score -= 15;
        } else if (explicitBrandHit || brandedIntent) {
          score += 16;
        }
        if (category == FoodSearchCategory.branded) {
          score += 15;
        }
        break;
    }

    if (!allTokensPresent &&
        queryTokens.length >= 2 &&
        result.resultType == FoodResultType.branded &&
        genericIntent) {
      score -= 25;
    }

    return score;
  }

  double substringEditDistanceScore({
    required String queryNormalized,
    required String candidateNormalized,
  }) {
    if (queryNormalized.isEmpty || candidateNormalized.isEmpty) {
      return 0;
    }
    if (candidateNormalized.contains(queryNormalized)) {
      return 1;
    }

    final queryLength = queryNormalized.length;
    final candidateLength = candidateNormalized.length;
    var bestDistance = queryLength + candidateLength;

    if (candidateLength <= queryLength + 2) {
      bestDistance = _damerauLevenshtein(
        queryNormalized,
        candidateNormalized,
        maxDistance: bestDistance,
      );
    } else {
      final baseWindow = queryLength + 2;
      final minWindow = max(4, queryLength - 2);
      final maxWindow = min(candidateLength, queryLength + 6);
      final maxStart = min(candidateLength - minWindow, 36);

      for (var start = 0; start <= maxStart; start++) {
        final windows = <int>{
          min(maxWindow, baseWindow),
          min(maxWindow, queryLength),
          min(maxWindow, minWindow),
        };
        for (final window in windows) {
          final end = start + window;
          if (end > candidateLength) continue;
          final sample = candidateNormalized.substring(start, end);
          final distance = _damerauLevenshtein(
            queryNormalized,
            sample,
            maxDistance: bestDistance,
          );
          if (distance < bestDistance) {
            bestDistance = distance;
            if (bestDistance == 0) break;
          }
        }
        if (bestDistance == 0) break;
      }
    }

    final similarity = 1 - (bestDistance / max(queryLength, 1));
    if (similarity.isNaN) return 0;
    return similarity.clamp(0.0, 1.0);
  }

  bool _isGenericFoodIntent({
    required String normalizedQuery,
    required List<String> queryTokens,
  }) {
    if (queryTokens.isEmpty || queryTokens.length > 3) {
      return false;
    }
    if (_isBrandedIntent(
      queryNormalized: normalizedQuery,
      queryTokens: queryTokens,
    )) {
      return false;
    }
    final genericHits = queryTokens.where(_genericFoodTerms.contains).length;
    if (genericHits >= 1) return true;
    return queryTokens.every((token) => token.length <= 10);
  }

  bool _isBrandedIntent({
    required String queryNormalized,
    required List<String> queryTokens,
  }) {
    if (queryTokens.any((token) => _brandHints.contains(token))) {
      return true;
    }
    // Tokens with mixed letters + digits often represent branded products.
    if (RegExp(r'[a-z]+\d|\d+[a-z]').hasMatch(queryNormalized)) {
      return true;
    }
    return false;
  }

  bool _isExplicitBrandHit({
    required String queryNormalized,
    required FoodSearchResult result,
  }) {
    final normalizedBrand = normalizeQuery(result.brand ?? '');
    if (normalizedBrand.isEmpty) return false;
    final brandTokens = tokenize(normalizedBrand);
    if (brandTokens.isEmpty) return false;
    return brandTokens.any((token) => queryNormalized.contains(token));
  }

  int _countMatchedTokens({
    required List<String> queryTokens,
    required List<String> candidateTokens,
    required String candidateName,
  }) {
    if (queryTokens.isEmpty) return 0;
    var matched = 0;
    for (final token in queryTokens) {
      if (_candidateHasToken(
        token: token,
        candidateTokens: candidateTokens,
        candidateName: candidateName,
      )) {
        matched += 1;
      }
    }
    return matched;
  }

  bool _candidateHasToken({
    required String token,
    required List<String> candidateTokens,
    required String candidateName,
  }) {
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

  bool _tokensInOrder({
    required List<String> queryTokens,
    required String candidateName,
  }) {
    if (queryTokens.length < 2) return false;
    var lastIndex = -1;
    for (final token in queryTokens) {
      final index = candidateName.indexOf(token, lastIndex + 1);
      if (index < 0) return false;
      lastIndex = index;
    }
    return true;
  }

  bool _tokensAdjacent({
    required List<String> queryTokens,
    required String candidateName,
  }) {
    if (queryTokens.length < 2) return false;
    final normalized = candidateName.replaceAll(RegExp(r'\s+'), ' ');
    final phrase = queryTokens.join(' ');
    if (normalized.contains(phrase)) return true;

    for (var i = 0; i < queryTokens.length - 1; i++) {
      final left = queryTokens[i];
      final right = queryTokens[i + 1];
      final leftIndex = normalized.indexOf(left);
      if (leftIndex < 0) return false;
      final nextSearchStart = leftIndex + left.length;
      if (nextSearchStart > normalized.length) return false;
      final rightIndex = normalized.indexOf(right, nextSearchStart);
      if (rightIndex < 0) return false;
      final gap = rightIndex - (leftIndex + left.length);
      if (gap > 5) return false;
    }
    return true;
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

  int _resultTypePriority(FoodResultType type) {
    return switch (type) {
      FoodResultType.generic => 0,
      FoodResultType.custom => 1,
      FoodResultType.branded => 2,
    };
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
