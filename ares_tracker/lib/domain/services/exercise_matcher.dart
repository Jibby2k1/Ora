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

  String normalize(String input) {
    final lowered = input.toLowerCase();
    final cleaned = lowered.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
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

    final tokens = normalized.split(' ');
    final tokenMatches = await _repo.findByTokenContains(tokens);
    if (tokenMatches.isEmpty) return ExerciseMatchResult.none();
    return tokenMatches.length == 1
        ? ExerciseMatchResult.single(_mapRows(tokenMatches))
        : ExerciseMatchResult.multiple(_mapRows(tokenMatches));
  }

  List<ExerciseMatch> _mapRows(List<Map<String, Object?>> rows) {
    return rows
        .map((row) => ExerciseMatch(
              id: row['id'] as int,
              name: row['canonical_name'] as String,
            ))
        .toList();
  }
}
