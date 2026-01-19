import 'voice_models.dart';

class NluParser {
  String normalize(String input) {
    final lowered = input.toLowerCase();
    final cleaned = lowered.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  NluCommand? parse(String input) {
    final text = normalize(input);
    if (text.isEmpty) return null;

    if (text == 'undo') return NluCommand(type: 'undo');
    if (text == 'redo') return NluCommand(type: 'redo');

    if (text.startsWith('rest ')) {
      final seconds = _parseRestSeconds(text.substring(5));
      return NluCommand(type: 'rest', restSeconds: seconds);
    }

    if (text.startsWith('switch to ')) {
      final ref = text.substring('switch to '.length).trim();
      return NluCommand(type: 'switch', exerciseRef: ref);
    }

    if (text.startsWith('show stats ')) {
      final ref = text.substring('show stats '.length).trim();
      return NluCommand(type: 'show_stats', exerciseRef: ref);
    }

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

    final xMatch = RegExp(r'^(.+?)\s+(\d+(?:\.\d+)?)\s*x\s*(\d+)').firstMatch(text);
    if (xMatch != null) {
      return NluCommand(
        type: 'log_set',
        exerciseRef: xMatch.group(1)?.trim(),
        weight: double.tryParse(xMatch.group(2) ?? ''),
        reps: int.tryParse(xMatch.group(3) ?? ''),
      );
    }

    final repsMatch = RegExp(r'^(.+?)\s+(\d+)\s+reps$').firstMatch(text);
    if (repsMatch != null) {
      return NluCommand(
        type: 'log_set',
        exerciseRef: repsMatch.group(1)?.trim(),
        reps: int.tryParse(repsMatch.group(2) ?? ''),
      );
    }

    return null;
  }

  _LogTail _parseLogTail(String text) {
    final partials = _matchInt(text, RegExp(r'(?:partials|partial)\s+(\d+)'));
    final rpe = _matchDouble(text, RegExp(r'rpe\s+(\d+(?:\.\d+)?)'));
    final rir = _matchDouble(text, RegExp(r'rir\s+(\d+(?:\.\d+)?)'));

    final xMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|kilograms|kilo|lbs|lb|pounds)?\s*x\s*(\d+)').firstMatch(text);
    if (xMatch != null) {
      return _LogTail(
        weight: double.tryParse(xMatch.group(1) ?? ''),
        weightUnit: _normalizeUnit(xMatch.group(2)),
        reps: int.tryParse(xMatch.group(3) ?? ''),
        partials: partials,
        rpe: rpe,
        rir: rir,
      );
    }

    final forMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|kilograms|kilo|lbs|lb|pounds)?\s+for\s+(\d+)').firstMatch(text);
    if (forMatch != null) {
      return _LogTail(
        weight: double.tryParse(forMatch.group(1) ?? ''),
        weightUnit: _normalizeUnit(forMatch.group(2)),
        reps: int.tryParse(forMatch.group(3) ?? ''),
        partials: partials,
        rpe: rpe,
        rir: rir,
      );
    }

    final repsMatch = RegExp(r'(\d+)\s+reps').firstMatch(text);
    if (repsMatch != null) {
      return _LogTail(
        reps: int.tryParse(repsMatch.group(1) ?? ''),
        partials: partials,
        rpe: rpe,
        rir: rir,
      );
    }

    final weightMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|kilograms|kilo|lbs|lb|pounds)').firstMatch(text);
    if (weightMatch != null) {
      return _LogTail(
        weight: double.tryParse(weightMatch.group(1) ?? ''),
        weightUnit: _normalizeUnit(weightMatch.group(2)),
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
    final secondMatch = RegExp(r'(\d+)\s*(second|seconds|sec)').firstMatch(text);
    if (secondMatch != null) {
      return int.tryParse(secondMatch.group(1) ?? '') ?? 0;
    }
    final plain = int.tryParse(text.trim());
    return plain ?? 0;
  }

  int? _matchInt(String text, RegExp regex) {
    final match = regex.firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  double? _matchDouble(String text, RegExp regex) {
    final match = regex.firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1) ?? '');
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
