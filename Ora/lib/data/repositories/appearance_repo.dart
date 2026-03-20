import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../domain/models/appearance_care.dart';
import '../../domain/models/appearance_entry.dart';
import '../db/db.dart';

class AppearanceRepo {
  AppearanceRepo(this._db);

  final AppDatabase _db;

  Future<int> addEntry({
    required DateTime createdAt,
    String? measurements,
    String? notes,
    String? imagePath,
  }) async {
    final db = await _db.database;
    return db.insert('appearance_entry', {
      'created_at': createdAt.toIso8601String(),
      'measurements': measurements,
      'notes': notes,
      'image_path': imagePath,
    });
  }

  Future<List<AppearanceEntry>> getRecentEntries({int limit = 20}) async {
    final db = await _db.database;
    final rows = await db.query(
      'appearance_entry',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  AppearanceEntry _fromRow(Map<String, Object?> row) {
    return AppearanceEntry(
      id: row['id'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      measurements: row['measurements'] as String?,
      notes: row['notes'] as String?,
      imagePath: row['image_path'] as String?,
    );
  }

  Future<void> updateEntry({
    required int id,
    String? measurements,
    String? notes,
    String? imagePath,
  }) async {
    final db = await _db.database;
    await db.update(
      'appearance_entry',
      {
        if (measurements != null) 'measurements': measurements,
        if (notes != null) 'notes': notes,
        if (imagePath != null) 'image_path': imagePath,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteEntry(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'appearance_entry',
      columns: ['image_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final path = rows.first['image_path'] as String?;
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // Ignore deletion failures to avoid blocking DB cleanup.
        }
      }
    }
    await db.delete('appearance_entry', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> saveStructuredAssessment(
      AppearanceAssessmentResult result) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final createdAt = result.generatedAt.toIso8601String();
      final assessmentId = await txn.insert('appearance_assessment', {
        'created_at': createdAt,
        'image_path': result.imagePath,
        'overall_summary': result.overallSummary,
        'direct_verdict': result.directVerdict,
        'questionnaire_json': jsonEncode(result.questionnaire.toJson()),
      });

      await txn.update(
        'appearance_plan',
        {'is_active': 0},
        where: 'is_active = 1',
      );

      for (final concern in result.candidateConcerns) {
        await txn.insert('appearance_concern', {
          'assessment_id': assessmentId,
          'concern_key': concern.concernKey,
          'domain': concern.domain,
          'title': concern.title,
          'confidence': concern.confidence,
          'severity': concern.severity,
          'evidence_summary': concern.evidenceSummary,
          'direct_feedback': concern.directFeedback,
          'intervention_tier': concern.interventionTier,
          'red_flag': concern.redFlag ? 1 : 0,
          'source_ids_json': jsonEncode(concern.sourceIds),
        });
      }

      for (final document in result.sourceDocuments) {
        await txn.insert(
          'appearance_source_document',
          {
            'id': document.normalizedId,
            'domain': document.domain,
            'title': document.title,
            'citation': document.citation,
            'url': document.url,
            'rationale': document.rationale,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final plan in result.plans) {
        final planId = await txn.insert('appearance_plan', {
          'assessment_id': assessmentId,
          'concern_key': plan.concernKey,
          'domain': plan.domain,
          'title': plan.title,
          'summary': plan.summary,
          'intervention_tier': plan.interventionTier,
          'current_phase': plan.currentPhase,
          'checkpoint_days_json': jsonEncode(plan.checkpointDays),
          'escalation_rules_json': jsonEncode(plan.escalationRules),
          'source_ids_json': jsonEncode(plan.sourceIds),
          'is_active': plan.active ? 1 : 0,
          'created_at': createdAt,
        });
        for (var index = 0; index < plan.steps.length; index += 1) {
          final step = plan.steps[index];
          await txn.insert('appearance_plan_step', {
            'plan_id': planId,
            'order_index': index,
            'phase_key': step.phaseKey,
            'title': step.title,
            'cadence': step.cadence,
            'duration_days': step.durationDays,
            'actions_json': jsonEncode(step.actions),
            'stop_conditions_json': jsonEncode(step.stopConditions),
          });
        }
      }

      return assessmentId;
    });
  }

  Future<AppearanceAssessmentResult?> getLatestStructuredAssessment() async {
    final db = await _db.database;
    final rows = await db.query(
      'appearance_assessment',
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    final assessmentId = row['id'] as int;
    final concerns = await _getConcernsForAssessment(db, assessmentId);
    final plans = await _getPlansForAssessment(db, assessmentId);
    final sourceIds = <String>{
      for (final concern in concerns) ...concern.sourceIds,
      for (final plan in plans) ...plan.sourceIds,
    };
    final documents = await getSourceDocuments(
      sourceIds: sourceIds.toList(),
      dbOverride: db,
    );
    return AppearanceAssessmentResult(
      assessmentId: assessmentId,
      imagePath: row['image_path'] as String?,
      questionnaire: AppearanceQuestionnaire.fromDynamic(
        _decodeJsonValue(row['questionnaire_json'] as String?),
      ),
      generatedAt: DateTime.parse(row['created_at'] as String),
      overallSummary: (row['overall_summary'] as String?) ?? '',
      directVerdict: (row['direct_verdict'] as String?) ?? '',
      candidateConcerns: concerns,
      plans: plans,
      sourceDocuments: documents,
    );
  }

  Future<List<AppearanceCarePlan>> getActivePlans() async {
    final db = await _db.database;
    final rows = await db.query(
      'appearance_plan',
      where: 'is_active = 1',
      orderBy: 'created_at DESC, id DESC',
    );
    return _mapPlans(db, rows);
  }

  Future<List<AppearanceProgressReview>> getRecentReviews({
    int limit = 30,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      """
SELECT r.id, r.plan_id, r.created_at, r.adherence, r.symptom_change,
       r.side_effects, r.notes, r.image_path, p.title AS plan_title
FROM appearance_review r
JOIN appearance_plan p ON p.id = r.plan_id
ORDER BY r.created_at DESC
LIMIT ?
""",
      [limit],
    );
    return rows.map((row) {
      return AppearanceProgressReview(
        id: row['id'] as int,
        planId: row['plan_id'] as int,
        createdAt: DateTime.parse(row['created_at'] as String),
        planTitle: row['plan_title'] as String?,
        adherence: row['adherence'] as int?,
        symptomChange: row['symptom_change'] as String?,
        sideEffects: row['side_effects'] as String?,
        notes: row['notes'] as String?,
        imagePath: row['image_path'] as String?,
      );
    }).toList();
  }

  Future<void> addProgressReview({
    required int planId,
    required DateTime createdAt,
    int? adherence,
    String? symptomChange,
    String? sideEffects,
    String? notes,
    String? imagePath,
  }) async {
    final db = await _db.database;
    await db.insert('appearance_review', {
      'plan_id': planId,
      'created_at': createdAt.toIso8601String(),
      'adherence': adherence,
      'symptom_change': _trimOrNull(symptomChange),
      'side_effects': _trimOrNull(sideEffects),
      'notes': _trimOrNull(notes),
      'image_path': _trimOrNull(imagePath),
    });
  }

  Future<List<AppearanceSourceDocument>> getSourceDocuments({
    List<String>? sourceIds,
    DatabaseExecutor? dbOverride,
  }) async {
    final db = dbOverride ?? await _db.database;
    final normalizedIds = (sourceIds ?? const <String>[])
        .map((id) => id.trim().toUpperCase().replaceAll(' ', ''))
        .where((id) => id.isNotEmpty)
        .toList();
    List<Map<String, Object?>> rows;
    if (normalizedIds.isEmpty) {
      rows = await db.query(
        'appearance_source_document',
        orderBy: 'domain ASC, title ASC',
      );
    } else {
      final placeholders = List.filled(normalizedIds.length, '?').join(',');
      rows = await db.query(
        'appearance_source_document',
        where: 'id IN ($placeholders)',
        whereArgs: normalizedIds,
        orderBy: 'domain ASC, title ASC',
      );
    }
    return rows.map(_sourceFromRow).toList();
  }

  Future<List<AppearanceCandidateConcern>> _getConcernsForAssessment(
    DatabaseExecutor db,
    int assessmentId,
  ) async {
    final rows = await db.query(
      'appearance_concern',
      where: 'assessment_id = ?',
      whereArgs: [assessmentId],
      orderBy: 'red_flag DESC, confidence DESC, id ASC',
    );
    return rows.map((row) {
      return AppearanceCandidateConcern(
        id: row['id'] as int,
        assessmentId: assessmentId,
        concernKey: row['concern_key'] as String,
        domain: row['domain'] as String,
        title: row['title'] as String,
        confidence: (row['confidence'] as num?)?.toDouble() ?? 0,
        severity: (row['severity'] as String?) ?? 'moderate',
        evidenceSummary: (row['evidence_summary'] as String?) ?? '',
        directFeedback: (row['direct_feedback'] as String?) ??
            (row['evidence_summary'] as String?) ??
            '',
        interventionTier: (row['intervention_tier'] as String?) ?? 'routine',
        redFlag: (row['red_flag'] as int? ?? 0) != 0,
        sourceIds: _decodeStringList(row['source_ids_json'] as String?),
      );
    }).toList();
  }

  Future<List<AppearanceCarePlan>> _getPlansForAssessment(
    DatabaseExecutor db,
    int assessmentId,
  ) async {
    final rows = await db.query(
      'appearance_plan',
      where: 'assessment_id = ?',
      whereArgs: [assessmentId],
      orderBy: 'created_at DESC, id ASC',
    );
    return _mapPlans(db, rows);
  }

  Future<List<AppearanceCarePlan>> _mapPlans(
    DatabaseExecutor db,
    List<Map<String, Object?>> rows,
  ) async {
    final plans = <AppearanceCarePlan>[];
    for (final row in rows) {
      final planId = row['id'] as int;
      final stepRows = await db.query(
        'appearance_plan_step',
        where: 'plan_id = ?',
        whereArgs: [planId],
        orderBy: 'order_index ASC',
      );
      final steps = stepRows.map((stepRow) {
        return AppearancePlanStep(
          phaseKey: (stepRow['phase_key'] as String?) ?? 'baseline_reset',
          title: (stepRow['title'] as String?) ?? 'Step',
          cadence: (stepRow['cadence'] as String?) ?? 'Daily',
          durationDays: stepRow['duration_days'] as int? ?? 14,
          actions: _decodeStringList(stepRow['actions_json'] as String?),
          stopConditions:
              _decodeStringList(stepRow['stop_conditions_json'] as String?),
        );
      }).toList();
      plans.add(
        AppearanceCarePlan(
          id: planId,
          assessmentId: row['assessment_id'] as int?,
          concernKey: row['concern_key'] as String,
          domain: row['domain'] as String,
          title: row['title'] as String,
          summary: row['summary'] as String,
          interventionTier: (row['intervention_tier'] as String?) ?? 'routine',
          currentPhase: (row['current_phase'] as String?) ?? 'baseline_reset',
          checkpointDays:
              _decodeIntList(row['checkpoint_days_json'] as String?),
          escalationRules:
              _decodeStringList(row['escalation_rules_json'] as String?),
          sourceIds: _decodeStringList(row['source_ids_json'] as String?),
          steps: steps,
          active: (row['is_active'] as int? ?? 0) != 0,
        ),
      );
    }
    return plans;
  }

  AppearanceSourceDocument _sourceFromRow(Map<String, Object?> row) {
    return AppearanceSourceDocument(
      id: row['id'] as String,
      domain: (row['domain'] as String?) ?? 'general',
      title: row['title'] as String,
      citation: row['citation'] as String,
      url: row['url'] as String?,
      rationale: row['rationale'] as String?,
    );
  }

  dynamic _decodeJsonValue(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(jsonString);
    } catch (_) {
      return null;
    }
  }

  List<String> _decodeStringList(String? jsonString) {
    final decoded = _decodeJsonValue(jsonString);
    if (decoded is! List) {
      return const [];
    }
    return [
      for (final item in decoded)
        if (item != null && item.toString().trim().isNotEmpty)
          item.toString().trim(),
    ];
  }

  List<int> _decodeIntList(String? jsonString) {
    final decoded = _decodeJsonValue(jsonString);
    if (decoded is! List) {
      return const [];
    }
    final values = <int>[];
    for (final item in decoded) {
      if (item is int) {
        values.add(item);
        continue;
      }
      if (item is double) {
        values.add(item.round());
        continue;
      }
      final parsed = int.tryParse(item?.toString() ?? '');
      if (parsed != null) {
        values.add(parsed);
      }
    }
    return values;
  }

  String? _trimOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
