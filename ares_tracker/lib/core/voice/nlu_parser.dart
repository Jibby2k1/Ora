import 'voice_models.dart';

class NluLogParts {
  NluLogParts({
    this.weight,
    this.weightUnit,
    this.reps,
    this.partials,
    this.rpe,
    this.rir,
  });

  final double? weight;
  final String? weightUnit;
  final int? reps;
  final int? partials;
  final double? rpe;
  final double? rir;
}

class NluParser {
  static const Map<String, int> _numberWords = {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  };
  static const Map<String, int> _tensWords = {
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };

  String normalize(String input) {
    final lowered = input.toLowerCase();
    final cleaned = lowered.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    final collapsed = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return collapsed;
    return _applyFixups(collapsed);
  }

  String _applyFixups(String text) {
    var value = text;
    const replacements = {
      'wraps': 'reps',
      'raps': 'reps',
      'repss': 'reps',
      'parcels': 'partials',
      'partial': 'partials',
      'rp ie': 'rpe',
      'rp e': 'rpe',
      'r p e': 'rpe',
      'when she': 'machine',
      'when shee': 'machine',
      'machines': 'machine',
      'lap poor down': 'lat pulldown',
      'lap pull down': 'lat pulldown',
      'dumb bell': 'dumbbell',
      'bar bell': 'barbell',
    };
    replacements.forEach((from, to) {
      value = value.replaceAll(' $from ', ' $to ');
      if (value.startsWith('$from ')) {
        value = '$to ${value.substring(from.length + 1)}';
      }
      if (value.endsWith(' $from')) {
        value = '${value.substring(0, value.length - from.length - 1)} $to';
      }
      if (value == from) value = to;
    });
    return value.trim();
  }

  NluCommand? parse(String input) {
    final text = normalize(input);
    if (text.isEmpty) return null;

    if (text == 'undo') return NluCommand(type: 'undo');
    if (text == 'redo') return NluCommand(type: 'redo');

    if (text.startsWith('switch to ')) {
      final ref = text.substring('switch to '.length).trim();
      return NluCommand(type: 'switch', exerciseRef: ref);
    }
    if (text.startsWith('switch ')) {
      final ref = text.substring('switch '.length).trim();
      return NluCommand(type: 'switch', exerciseRef: ref);
    }

    if (text.startsWith('show stats ')) {
      final ref = text.substring('show stats '.length).trim();
      return NluCommand(type: 'show_stats', exerciseRef: ref);
    }
    if (text == 'show stats') {
      return NluCommand(type: 'show_stats');
    }

    final logCommand = _parseLogCommand(text);
    if (logCommand != null) return logCommand;

    return null;
  }

  double? parseWeightOnly(String input) {
    final text = normalize(input);
    if (text.isEmpty) return null;
    final match = RegExp(r'(.+?)(?:\s*(kg|kilograms|kilo|lbs|lb|pounds))?$')
        .firstMatch(text);
    if (match == null) return null;
    return _parseNumberValue(match.group(1)?.trim() ?? '');
  }

  NluLogParts parseLogParts(String input) {
    final text = normalize(input);
    final tail = _parseLogTail(text);
    var reps = tail.reps;
    var weight = tail.weight;

    if (reps == null || weight == null) {
      final numbers = _extractNumbers(text);
      if (numbers.isNotEmpty) {
        if (reps == null) {
          reps = numbers.last.toInt();
        }
        if (weight == null && numbers.length >= 2) {
          weight = numbers[numbers.length - 2];
        }
      }
    }

    return NluLogParts(
      weight: weight,
      weightUnit: tail.weightUnit,
      reps: reps,
      partials: tail.partials,
      rpe: tail.rpe,
      rir: tail.rir,
    );
  }

  NluLogParts parseLogPartsWithOrderHints(String input) {
    final base = parseLogParts(input);
    final normalized = normalize(input);
    if (normalized.isEmpty) return base;

    final reps = _extractNumberBeforeKeywordTokens(normalized, 'reps');
    final weight = _extractNumberBeforeUnitTokens(normalized);
    final weightUnit = _extractWeightUnit(normalized);

    return NluLogParts(
      weight: weight ?? base.weight,
      weightUnit: weightUnit ?? base.weightUnit,
      reps: reps ?? base.reps,
      partials: base.partials,
      rpe: base.rpe,
      rir: base.rir,
    );
  }

  NluCommand? _parseLogCommand(String text) {
    final extras = _parseLogTail(text);

    final commaParts = text.split(',');
    if (commaParts.length >= 2) {
      final exerciseRef = commaParts.first.trim();
      final rest = commaParts.sublist(1).join(',').trim();
      final parsed = _parseLogTail(rest);
      return NluCommand(
        type: 'log_set',
        exerciseRef: exerciseRef,
        weight: parsed.weight,
        weightUnit: parsed.weightUnit,
        reps: parsed.reps,
        partials: parsed.partials,
        rpe: parsed.rpe,
        rir: parsed.rir,
      );
    }

    final forMatch = RegExp(
      r'^(.+?)\s+(.+?)\s*(kg|kilograms|kilo|lbs|lb|pounds)?\s+for\s+(.+?)(?:\s+reps)?$',
    ).firstMatch(text);
    if (forMatch != null) {
      final weight = _parseNumberValue(forMatch.group(2)?.trim() ?? '');
      final reps = _parseIntValue(forMatch.group(4)?.trim() ?? '');
      return NluCommand(
        type: 'log_set',
        exerciseRef: forMatch.group(1)?.trim(),
        weight: weight,
        weightUnit: _normalizeUnit(forMatch.group(3)),
        reps: reps,
        partials: extras.partials,
        rpe: extras.rpe,
        rir: extras.rir,
      );
    }

    final xMatch = RegExp(
      r'^(.+?)\s+(.+?)\s*(kg|kilograms|kilo|lbs|lb|pounds)?\s*x\s*(.+?)$',
    ).firstMatch(text);
    if (xMatch != null) {
      final weight = _parseNumberValue(xMatch.group(2)?.trim() ?? '');
      final reps = _parseIntValue(xMatch.group(4)?.trim() ?? '');
      return NluCommand(
        type: 'log_set',
        exerciseRef: xMatch.group(1)?.trim(),
        weight: weight,
        weightUnit: _normalizeUnit(xMatch.group(3)),
        reps: reps,
        partials: extras.partials,
        rpe: extras.rpe,
        rir: extras.rir,
      );
    }

    final repsMatch = RegExp(r'^(.+?)\s+(.+?)\s+reps$').firstMatch(text);
    if (repsMatch != null) {
      final reps = _parseIntValue(repsMatch.group(2)?.trim() ?? '');
      return NluCommand(
        type: 'log_set',
        exerciseRef: repsMatch.group(1)?.trim(),
        reps: reps,
        partials: extras.partials,
        rpe: extras.rpe,
        rir: extras.rir,
      );
    }

    final plainNumberMatch = RegExp(r'^(.+?)\s+(\d+)$').firstMatch(text);
    if (plainNumberMatch != null) {
      return NluCommand(
        type: 'log_set',
        exerciseRef: plainNumberMatch.group(1)?.trim(),
        reps: int.tryParse(plainNumberMatch.group(2) ?? ''),
        partials: extras.partials,
        rpe: extras.rpe,
        rir: extras.rir,
      );
    }

    return null;
  }

  _LogTail _parseLogTail(String text) {
    final partials = _matchInt(
      text,
      RegExp(r'(?:partials|partial)\s+(\d+)|(?:and|plus)\s+(\d+)\s+partials'),
    );
    final rpe = _matchDouble(text, RegExp(r'rpe\s+(\d+(?:\.\d+)?)'));
    final rir = _matchDouble(text, RegExp(r'rir\s+(\d+(?:\.\d+)?)'));

    final xMatch = RegExp(r'(.+?)\s*(kg|kilograms|kilo|lbs|lb|pounds)?\s*x\s*(.+)').firstMatch(text);
    if (xMatch != null) {
      return _LogTail(
        weight: _parseNumberValue(xMatch.group(1)?.trim() ?? ''),
        weightUnit: _normalizeUnit(xMatch.group(2)),
        reps: _parseIntValue(xMatch.group(3)?.trim() ?? ''),
        partials: partials,
        rpe: rpe,
        rir: rir,
      );
    }

    final forMatch = RegExp(r'(.+?)\s*(kg|kilograms|kilo|lbs|lb|pounds)?\s+for\s+(.+)').firstMatch(text);
    if (forMatch != null) {
      return _LogTail(
        weight: _parseNumberValue(forMatch.group(1)?.trim() ?? ''),
        weightUnit: _normalizeUnit(forMatch.group(2)),
        reps: _parseIntValue(forMatch.group(3)?.trim() ?? ''),
        partials: partials,
        rpe: rpe,
        rir: rir,
      );
    }

    final repsMatch = RegExp(r'(.+?)\s+reps').firstMatch(text);
    if (repsMatch != null) {
      return _LogTail(
        reps: _parseIntValue(repsMatch.group(1)?.trim() ?? ''),
        partials: partials,
        rpe: rpe,
        rir: rir,
      );
    }

    final weightMatch = RegExp(r'(.+?)\s*(kg|kilograms|kilo|lbs|lb|pounds)').firstMatch(text);
    if (weightMatch != null) {
      return _LogTail(
        weight: _parseNumberValue(weightMatch.group(1)?.trim() ?? ''),
        weightUnit: _normalizeUnit(weightMatch.group(2)),
        partials: partials,
        rpe: rpe,
        rir: rir,
      );
    }

    final numberMatch = RegExp(r'^\s*(\d+)\s*$').firstMatch(text);
    if (numberMatch != null) {
      return _LogTail(
        reps: int.tryParse(numberMatch.group(1) ?? ''),
        partials: partials,
        rpe: rpe,
        rir: rir,
      );
    }

    return _LogTail(partials: partials, rpe: rpe, rir: rir);
  }

  int _parseRestSeconds(String text) {
    final minuteMatch = RegExp(r'(\d+)\s*(minute|minutes|min)').firstMatch(text);
    if (minuteMatch != null) {
      final minutes = int.tryParse(minuteMatch.group(1) ?? '') ?? 0;
      return minutes * 60;
    }
    final minuteWordMatch = RegExp(r'([a-z ]+)\s*(minute|minutes|min)').firstMatch(text);
    if (minuteWordMatch != null) {
      final minutes = _parseIntValue(minuteWordMatch.group(1)?.trim() ?? '') ?? 0;
      return minutes * 60;
    }
    final secondMatch = RegExp(r'(\d+)\s*(second|seconds|sec)').firstMatch(text);
    if (secondMatch != null) {
      return int.tryParse(secondMatch.group(1) ?? '') ?? 0;
    }
    final secondWordMatch = RegExp(r'([a-z ]+)\s*(second|seconds|sec)').firstMatch(text);
    if (secondWordMatch != null) {
      return _parseIntValue(secondWordMatch.group(1)?.trim() ?? '') ?? 0;
    }
    final plain = int.tryParse(text.trim());
    if (plain != null) return plain;
    return _parseIntValue(text.trim()) ?? 0;
  }

  int? _matchInt(String text, RegExp regex) {
    final match = regex.firstMatch(text);
    if (match == null) return null;
    final raw = match.group(1) ?? match.group(2) ?? '';
    return int.tryParse(raw);
  }

  double? _matchDouble(String text, RegExp regex) {
    final match = regex.firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1) ?? '');
  }

  int? _parseIntValue(String raw) {
    final numeric = double.tryParse(raw);
    if (numeric != null) return numeric.round();
    return _parseNumberWords(raw);
  }

  double? _parseNumberValue(String raw) {
    final numeric = double.tryParse(raw);
    if (numeric != null) return numeric;
    final word = _parseNumberWords(raw);
    if (word == null) return null;
    return word.toDouble();
  }

  int? _extractNumberBeforeKeywordTokens(String text, String keyword) {
    final tokens = text.split(' ').where((t) => t.isNotEmpty).toList();
    final idx = tokens.lastIndexWhere((t) => t == keyword);
    if (idx <= 0) return null;
    return _parseNumberFromTokens(tokens, idx - 1);
  }

  double? _extractNumberBeforeUnitTokens(String text) {
    final tokens = text.split(' ').where((t) => t.isNotEmpty).toList();
    final idx = tokens.lastIndexWhere((t) =>
        t == 'lb' ||
        t == 'lbs' ||
        t == 'pounds' ||
        t == 'kg' ||
        t == 'kilo' ||
        t == 'kilograms');
    if (idx <= 0) return null;
    final value = _parseNumberFromTokens(tokens, idx - 1);
    return value?.toDouble();
  }

  String? _extractWeightUnit(String text) {
    final match =
        RegExp(r'\b(kg|kilograms|kilo|lbs|lb|pounds)\b').firstMatch(text);
    if (match == null) return null;
    return _normalizeUnit(match.group(1));
  }

  int? _parseNumberFromTokens(List<String> tokens, int endIndex) {
    if (endIndex < 0) return null;
    final token = tokens[endIndex];
    if (token == 'for' || token == 'fore') {
      return 4;
    }
    final start = endIndex - 3 < 0 ? 0 : endIndex - 3;
    for (var i = start; i <= endIndex; i++) {
      final slice = tokens.sublist(i, endIndex + 1);
      final joined = slice.join(' ');
      final direct = int.tryParse(joined);
      if (direct != null) return direct;
      final word = _parseNumberWords(joined);
      if (word != null) return word;
    }
    final single = int.tryParse(tokens[endIndex]);
    if (single != null) return single;
    return _parseNumberWords(tokens[endIndex]);
  }

  List<double> _extractNumbers(String text) {
    final tokens = text.split(' ').where((t) => t.isNotEmpty).toList();
    final numbers = <double>[];
    var i = 0;
    while (i < tokens.length) {
      final direct = double.tryParse(tokens[i]);
      if (direct != null) {
        numbers.add(direct);
        i += 1;
        continue;
      }

      double? parsed;
      var bestLen = 0;
      final maxLen = (i + 4 <= tokens.length) ? 4 : tokens.length - i;
      for (var len = 1; len <= maxLen; len++) {
        final slice = tokens.sublist(i, i + len).join(' ');
        final value = _parseNumberWords(slice);
        if (value != null && len > bestLen) {
          parsed = value.toDouble();
          bestLen = len;
        }
      }
      if (parsed != null && bestLen > 0) {
        numbers.add(parsed);
        i += bestLen;
        continue;
      }

      i += 1;
    }
    return numbers;
  }

  int? _parseNumberWords(String raw) {
    final tokens = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;

    final hasHundred = tokens.contains('hundred');
    if (!hasHundred &&
        tokens.length >= 2 &&
        _numberWords.containsKey(tokens.first) &&
        _tensWords.containsKey(tokens[1])) {
      final hundreds = _numberWords[tokens.first] ?? 0;
      final rest = _parseNumberWords(tokens.sublist(1).join(' ')) ?? 0;
      return (hundreds * 100) + rest;
    }

    var total = 0;
    var current = 0;
    var used = false;
    for (final token in tokens) {
      if (_numberWords.containsKey(token)) {
        current += _numberWords[token]!;
        used = true;
        continue;
      }
      if (_tensWords.containsKey(token)) {
        current += _tensWords[token]!;
        used = true;
        continue;
      }
      if (token == 'hundred') {
        if (current == 0) current = 1;
        current *= 100;
        used = true;
        continue;
      }
      if (token == 'thousand') {
        if (current == 0) current = 1;
        total += current * 1000;
        current = 0;
        used = true;
        continue;
      }
      return null;
    }
    total += current;
    return used ? total : null;
  }

  String? _normalizeUnit(String? raw) {
    if (raw == null) return null;
    if (raw.startsWith('kg')) return 'kg';
    if (raw.startsWith('kilo')) return 'kg';
    if (raw.startsWith('lb') || raw.startsWith('pound')) return 'lb';
    return null;
  }
}

class _LogTail {
  _LogTail({
    this.weight,
    this.weightUnit,
    this.reps,
    this.partials,
    this.rpe,
    this.rir,
  });

  final double? weight;
  final String? weightUnit;
  final int? reps;
  final int? partials;
  final double? rpe;
  final double? rir;
}
