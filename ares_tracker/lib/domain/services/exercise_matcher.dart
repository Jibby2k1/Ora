import '../../data/repositories/exercise_repo.dart';

class ExerciseMatch {
  ExerciseMatch({required this.id, required this.name});

  final int id;
  final String name;
}

class ExerciseMatchResult {
  ExerciseMatchResult.none() : matches = const [];
  ExerciseMatchResult.single(this.matches);
  ExerciseMatchResult.multiple(this.matches);

  final List<ExerciseMatch> matches;

  bool get isNone => matches.isEmpty;
  bool get isSingle => matches.length == 1;
  bool get isMultiple => matches.length > 1;
}

class ExerciseMatcher {
  ExerciseMatcher(this._repo);

  final ExerciseRepo _repo;

  static const double _minScore = 0.5;
  static const double _scoreMargin = 0.12;

  final Map<int, _ExerciseIndexEntry> _indexById = {};
  bool _indexReady = false;

  String normalize(String input) {
    final lowered = input.toLowerCase();
    final cleaned = lowered.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    final collapsed = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return collapsed;
    return _applyPhraseFixups(collapsed);
  }

  String normalizeForCache(String input) {
    final tokens = tokenize(input).toList()..sort();
    return tokens.join(' ');
  }

  Set<String> tokenize(String input) {
    final normalized = normalize(input);
    if (normalized.isEmpty) return {};
    final rawTokens = normalized.split(' ');
    final fixed = <String>[];
    for (final token in rawTokens) {
      final clean = _applyTokenFixups(token);
      if (clean.isEmpty) continue;
      if (_stopTokens.contains(clean)) continue;
      if (_isNumeric(clean)) continue;
      fixed.add(clean);
    }
    return _mergeCompounds(fixed).toSet();
  }

  double scoreName(String input, String candidate) {
    final inputTokens = tokenize(input);
    final candidateTokens = tokenize(candidate);
    if (inputTokens.isEmpty || candidateTokens.isEmpty) return 0.0;
    final entry = _ExerciseIndexEntry(
      id: 0,
      name: candidate,
      tokens: candidateTokens,
      essentialTokens: _essentialTokens(candidateTokens),
      aliasTokens: const [],
    );
    return _scoreEntry(inputTokens, entry);
  }

  Future<ExerciseMatchResult> match(String exerciseRef) async {
    final normalized = normalize(exerciseRef);
    if (normalized.isEmpty) return ExerciseMatchResult.none();

    final canonical = await _repo.findByCanonical(normalized);
    if (canonical.isNotEmpty) {
      return ExerciseMatchResult.single(_mapRows(canonical));
    }

    final alias = await _repo.findByAlias(normalized);
    if (alias.isNotEmpty) {
      return alias.length == 1
          ? ExerciseMatchResult.single(_mapRows(alias))
          : ExerciseMatchResult.multiple(_mapRows(alias));
    }

    await _ensureIndex();
    if (_indexById.isEmpty) return ExerciseMatchResult.none();

    final inputTokens = tokenize(exerciseRef);
    if (inputTokens.isEmpty) return ExerciseMatchResult.none();

    final scored = <_ExerciseMatchScore>[];
    for (final entry in _indexById.values) {
      final score = _scoreEntry(inputTokens, entry);
      if (score >= _minScore) {
        scored.add(_ExerciseMatchScore(entry.id, entry.name, score));
      }
    }
    if (scored.isEmpty) return ExerciseMatchResult.none();
    scored.sort((a, b) => b.score.compareTo(a.score));

    if (scored.length == 1) {
      return ExerciseMatchResult.single(_mapScores(scored.take(1).toList()));
    }
    if (scored.first.score - scored[1].score >= _scoreMargin) {
      return ExerciseMatchResult.single(_mapScores(scored.take(1).toList()));
    }
    return ExerciseMatchResult.multiple(_mapScores(scored));
  }

  Future<void> _ensureIndex() async {
    if (_indexReady) return;
    _indexById.clear();
    final exercises = await _repo.getAll();
    final aliasRows = await _repo.getAllAliases();
    final aliasMap = <int, List<String>>{};
    for (final row in aliasRows) {
      final id = row['exercise_id'] as int?;
      final alias = row['alias_normalized'] as String?;
      if (id == null || alias == null || alias.isEmpty) continue;
      aliasMap.putIfAbsent(id, () => []).add(alias);
    }
    for (final row in exercises) {
      final id = row['id'] as int?;
      final name = row['canonical_name'] as String?;
      if (id == null || name == null) continue;
      final tokens = tokenize(name);
      final essential = _essentialTokens(tokens);
      final aliasTokens = <Set<String>>[];
      for (final alias in aliasMap[id] ?? const []) {
        final aliasSet = tokenize(alias);
        if (aliasSet.isNotEmpty) {
          aliasTokens.add(aliasSet);
        }
      }
      _indexById[id] = _ExerciseIndexEntry(
        id: id,
        name: name,
        tokens: tokens,
        essentialTokens: essential,
        aliasTokens: aliasTokens,
      );
    }
    _indexReady = true;
  }

  double _scoreEntry(Set<String> inputTokens, _ExerciseIndexEntry entry) {
    double best = 0.0;
    best = _maxScore(
        best,
        _applyDirectionPenalty(
          _applyEssentialPenalty(
            _scoreTokens(inputTokens, entry.tokens),
            inputTokens,
            entry.essentialTokens,
          ),
          inputTokens,
          entry.tokens,
        ));
    best = _maxScore(
        best,
        _applyDirectionPenalty(
          _applyEssentialPenalty(
            _scoreTokens(inputTokens, entry.essentialTokens),
            inputTokens,
            entry.essentialTokens,
          ),
          inputTokens,
          entry.essentialTokens,
        ));
    for (final alias in entry.aliasTokens) {
      final essentialAlias = _essentialTokens(alias);
      best = _maxScore(
          best,
          _applyDirectionPenalty(
            _applyEssentialPenalty(
              _scoreTokens(inputTokens, alias),
              inputTokens,
              essentialAlias,
            ),
            inputTokens,
            alias,
          ));
      best = _maxScore(
          best,
          _applyDirectionPenalty(
            _applyEssentialPenalty(
              _scoreTokens(inputTokens, essentialAlias),
              inputTokens,
              essentialAlias,
            ),
            inputTokens,
            essentialAlias,
          ));
    }
    return best;
  }

  double _maxScore(double current, double next) => next > current ? next : current;

  double _scoreTokens(Set<String> input, Set<String> candidate) {
    if (input.isEmpty || candidate.isEmpty) return 0.0;
    final overlap = input.intersection(candidate);
    if (overlap.isEmpty) return 0.0;
    final inputWeight = _sumWeights(input);
    final candidateWeight = _sumWeights(candidate);
    final overlapWeight = _sumWeights(overlap);
    final denom = candidateWeight + (inputWeight * 0.35);
    var score = denom == 0 ? 0.0 : (overlapWeight / denom);
    if (overlap.length == candidate.length) score += 0.08;
    if (overlap.length == input.length) score += 0.04;
    if (score > 1.0) score = 1.0;
    return score;
  }

  double _applyEssentialPenalty(double score, Set<String> input, Set<String> essential) {
    if (score <= 0 || essential.isEmpty) return score;
    final overlap = input.intersection(essential).length;
    final coverage = overlap / essential.length;
    if (coverage >= 0.75) return score;
    final factor = 0.45 + (0.55 * coverage);
    return score * factor;
  }

  double _applyDirectionPenalty(double score, Set<String> input, Set<String> candidate) {
    if (score <= 0) return score;
    final required = input.intersection(_directionTokens);
    if (required.isEmpty) return score;
    final overlap = candidate.intersection(required);
    if (overlap.length == required.length) return score;
    return score * 0.55;
  }

  double _sumWeights(Set<String> tokens) {
    var total = 0.0;
    for (final token in tokens) {
      total += _tokenWeight(token);
    }
    return total;
  }

  double _tokenWeight(String token) {
    if (_veryCommonTokens.contains(token)) return 0.3;
    if (_moderateTokens.contains(token)) return 0.7;
    return 1.0;
  }

  Set<String> _essentialTokens(Set<String> tokens) {
    final essential = tokens
        .where((t) => !_veryCommonTokens.contains(t) && !_moderateTokens.contains(t))
        .toSet();
    return essential.isEmpty ? tokens : essential;
  }

  String _applyPhraseFixups(String text) {
    var value = ' $text ';
    for (final entry in _phraseFixups.entries) {
      value = value.replaceAll(' ${entry.key} ', ' ${entry.value} ');
    }
    return value.trim();
  }

  String _applyTokenFixups(String token) {
    return _tokenFixups[token] ?? token;
  }

  Set<String> _mergeCompounds(List<String> tokens) {
    if (tokens.isEmpty) return {};
    final merged = <String>[];
    var i = 0;
    while (i < tokens.length) {
      final current = tokens[i];
      if (i + 1 < tokens.length) {
        final next = tokens[i + 1];
        final key = '$current $next';
        final compound = _compoundFixups[key];
        if (compound != null) {
          merged.add(compound);
          i += 2;
          continue;
        }
      }
      merged.add(current);
      i += 1;
    }
    return merged.toSet();
  }

  bool _isNumeric(String token) {
    return RegExp(r'^\d+(?:\.\d+)?$').hasMatch(token);
  }

  List<ExerciseMatch> _mapRows(List<Map<String, Object?>> rows) {
    return rows
        .map((row) => ExerciseMatch(
              id: row['id'] as int,
              name: row['canonical_name'] as String,
            ))
        .toList();
  }

  List<ExerciseMatch> _mapScores(List<_ExerciseMatchScore> scores) {
    return scores
        .map((score) => ExerciseMatch(
              id: score.id,
              name: score.name,
            ))
        .toList();
  }
}

class _ExerciseIndexEntry {
  _ExerciseIndexEntry({
    required this.id,
    required this.name,
    required this.tokens,
    required this.essentialTokens,
    required this.aliasTokens,
  });

  final int id;
  final String name;
  final Set<String> tokens;
  final Set<String> essentialTokens;
  final List<Set<String>> aliasTokens;
}

class _ExerciseMatchScore {
  _ExerciseMatchScore(this.id, this.name, this.score);

  final int id;
  final String name;
  final double score;
}

const Map<String, String> _phraseFixups = {
  'lap pull down': 'lat pulldown',
  'lap poor down': 'lat pulldown',
  'lat pull down': 'lat pulldown',
  'pull down': 'pulldown',
  'pull up': 'pullup',
  'dumb bell': 'dumbbell',
  'bar bell': 'barbell',
  'pec deck': 'pec deck',
  'peck deck': 'pec deck',
  'face pause': 'face pulls',
  'when she': 'machine',
  'when shee': 'machine',
  'she just': 'machine',
};

const Map<String, String> _compoundFixups = {
  'pull down': 'pulldown',
  'pull up': 'pullup',
  'pec deck': 'pecdeck',
};

const Map<String, String> _tokenFixups = {
  'machines': 'machine',
  'machined': 'machine',
  'cd': 'seated',
  'peck': 'pec',
  'pecs': 'pec',
  'pec\'s': 'pec',
  'lats': 'lat',
  'presses': 'press',
  'curls': 'curl',
  'rows': 'row',
  'raises': 'raise',
  'extensions': 'extension',
  'flies': 'fly',
  'flyes': 'fly',
  'inclined': 'incline',
  'declined': 'decline',
  'pulldowns': 'pulldown',
  'pushdowns': 'pushdown',
  'pressdowns': 'pressdown',
};

// Common transcript tokens (from transcript_keywords.json) to down-weight modifiers.
const Set<String> _veryCommonTokens = {
  'machine',
  'dumbbell',
  'cable',
  'barbell',
  'press',
  'curl',
  'row',
  'grip',
  'tricep',
  'triceps',
  'bicep',
  'biceps',
  'pressdown',
  'pushdown',
  'pulldown',
  'pullover',
  'raise',
  'extension',
  'fly',
  'arm',
  'rear',
  'front',
  'side',
  'lateral',
  'hammer',
  'reverse',
  'underhand',
  'overhand',
  'neutral',
  'wide',
  'close',
  'narrow',
  'high',
  'low',
  'standing',
  'lying',
  'flat',
  'cross',
  'smith',
  'rope',
  'ez',
  'straight',
  'plate',
  'dual',
  'supported',
  'vertical',
  'horizontal',
  'assisted',
  'rearward',
};

const Set<String> _moderateTokens = {
  'chest',
  'shoulder',
  'leg',
  'incline',
  'decline',
  'pec',
  'pecdeck',
  'lat',
  'hamstring',
  'quad',
  'glute',
  'hip',
  'calf',
  'adductor',
  'abductor',
  'upper',
  'lower',
  'mid',
  'inner',
  'outer',
};

const Set<String> _stopTokens = {
  'rep',
  'reps',
  'set',
  'sets',
  'lb',
  'lbs',
  'pound',
  'pounds',
  'kg',
  'kilo',
  'kilos',
  'kilogram',
  'kilograms',
  'rpe',
  'rir',
  'partial',
  'partials',
  'and',
  'plus',
  'for',
  'x',
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
  'hundred',
  'thousand',
  'million',
  'point',
};

const Set<String> _directionTokens = {
  'incline',
  'decline',
  'flat',
  'vertical',
  'horizontal',
};
