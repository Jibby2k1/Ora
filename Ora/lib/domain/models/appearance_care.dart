class AppearanceQuestionnaire {
  const AppearanceQuestionnaire({
    this.domains = const [],
    this.diagnosedConditions = const [],
    this.mainConcerns = const [],
    this.symptoms = const [],
    this.goals = const [],
    this.history,
    this.currentRoutine,
    this.styleContext,
    this.profileSex,
  });

  final List<String> domains;
  final List<String> diagnosedConditions;
  final List<String> mainConcerns;
  final List<String> symptoms;
  final List<String> goals;
  final String? history;
  final String? currentRoutine;
  final String? styleContext;
  final String? profileSex;

  bool get hasContent {
    return domains.isNotEmpty ||
        diagnosedConditions.isNotEmpty ||
        mainConcerns.isNotEmpty ||
        symptoms.isNotEmpty ||
        goals.isNotEmpty ||
        (history?.trim().isNotEmpty ?? false) ||
        (currentRoutine?.trim().isNotEmpty ?? false) ||
        (styleContext?.trim().isNotEmpty ?? false) ||
        (profileSex?.trim().isNotEmpty ?? false);
  }

  Map<String, Object?> toJson() {
    return {
      'domains': domains,
      'diagnosed_conditions': diagnosedConditions,
      'main_concerns': mainConcerns,
      'symptoms': symptoms,
      'goals': goals,
      if (history != null && history!.trim().isNotEmpty) 'history': history,
      if (currentRoutine != null && currentRoutine!.trim().isNotEmpty)
        'current_routine': currentRoutine,
      if (styleContext != null && styleContext!.trim().isNotEmpty)
        'style_context': styleContext,
      if (profileSex != null && profileSex!.trim().isNotEmpty)
        'profile_sex': profileSex,
    };
  }

  static AppearanceQuestionnaire fromDynamic(dynamic raw) {
    final map = _asStringKeyMap(raw);
    if (map == null) {
      return const AppearanceQuestionnaire();
    }
    return AppearanceQuestionnaire(
      domains: _stringList(map['domains']),
      diagnosedConditions: _stringList(
        map['diagnosed_conditions'] ?? map['diagnoses'],
      ),
      mainConcerns: _stringList(map['main_concerns'] ?? map['concerns']),
      symptoms: _stringList(map['symptoms']),
      goals: _stringList(map['goals']),
      history: _firstNonEmptyString(map, ['history']),
      currentRoutine: _firstNonEmptyString(
        map,
        ['current_routine', 'routine'],
      ),
      styleContext: _firstNonEmptyString(
        map,
        ['style_context', 'grooming_context'],
      ),
      profileSex: _firstNonEmptyString(map, ['profile_sex', 'sex']),
    );
  }
}

class AppearanceSourceDocument {
  const AppearanceSourceDocument({
    required this.id,
    required this.domain,
    required this.title,
    required this.citation,
    this.url,
    this.rationale,
  });

  final String id;
  final String domain;
  final String title;
  final String citation;
  final String? url;
  final String? rationale;

  String get normalizedId => _normalizeSourceId(id);

  Map<String, Object?> toJson() {
    return {
      'id': normalizedId,
      'domain': domain,
      'title': title,
      'citation': citation,
      if (url != null && url!.trim().isNotEmpty) 'url': url,
      if (rationale != null && rationale!.trim().isNotEmpty)
        'rationale': rationale,
    };
  }

  static List<AppearanceSourceDocument> listFromDynamic(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    final documents = <AppearanceSourceDocument>[];
    final seen = <String>{};
    for (final item in raw) {
      final document = fromDynamic(item, fallbackIndex: documents.length + 1);
      if (document == null) {
        continue;
      }
      if (seen.add(document.normalizedId)) {
        documents.add(document);
      }
    }
    return documents;
  }

  static AppearanceSourceDocument? fromDynamic(
    dynamic raw, {
    int fallbackIndex = 1,
  }) {
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      final citation = raw.trim();
      if (citation.isEmpty) {
        return null;
      }
      return AppearanceSourceDocument(
        id: 'SRC$fallbackIndex',
        domain: 'general',
        title: citation,
        citation: citation,
      );
    }
    final map = _asStringKeyMap(raw);
    if (map == null) {
      return null;
    }
    final citation = _firstNonEmptyString(
      map,
      ['citation', 'reference', 'text'],
    );
    final title = _firstNonEmptyString(map, ['title']) ?? citation;
    if (title == null || title.trim().isEmpty) {
      return null;
    }
    return AppearanceSourceDocument(
      id: _firstNonEmptyString(map, ['id', 'source_id', 'document_id']) ??
          'SRC$fallbackIndex',
      domain: _firstNonEmptyString(map, ['domain']) ?? 'general',
      title: title.trim(),
      citation: (citation ?? title).trim(),
      url: _firstNonEmptyString(map, ['url', 'link']),
      rationale: _firstNonEmptyString(map, ['rationale', 'note', 'summary']),
    );
  }
}

class AppearanceCandidateConcern {
  const AppearanceCandidateConcern({
    this.id,
    this.assessmentId,
    required this.concernKey,
    required this.domain,
    required this.title,
    required this.confidence,
    required this.severity,
    required this.evidenceSummary,
    required this.directFeedback,
    required this.interventionTier,
    this.redFlag = false,
    this.sourceIds = const [],
  });

  final int? id;
  final int? assessmentId;
  final String concernKey;
  final String domain;
  final String title;
  final double confidence;
  final String severity;
  final String evidenceSummary;
  final String directFeedback;
  final String interventionTier;
  final bool redFlag;
  final List<String> sourceIds;

  Map<String, Object?> toJson() {
    return {
      if (id != null) 'id': id,
      if (assessmentId != null) 'assessment_id': assessmentId,
      'concern_key': concernKey,
      'domain': domain,
      'title': title,
      'confidence': confidence,
      'severity': severity,
      'evidence_summary': evidenceSummary,
      'direct_feedback': directFeedback,
      'intervention_tier': interventionTier,
      'red_flag': redFlag,
      'source_ids': sourceIds,
    };
  }

  static List<AppearanceCandidateConcern> listFromDynamic(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    final concerns = <AppearanceCandidateConcern>[];
    for (final item in raw) {
      final concern = fromDynamic(item);
      if (concern != null) {
        concerns.add(concern);
      }
    }
    return concerns;
  }

  static AppearanceCandidateConcern? fromDynamic(dynamic raw) {
    final map = _asStringKeyMap(raw);
    if (map == null) {
      return null;
    }
    final key = _firstNonEmptyString(map, ['concern_key', 'key', 'id']);
    final title = _firstNonEmptyString(map, ['title', 'label']);
    final evidenceSummary = _firstNonEmptyString(
      map,
      ['evidence_summary', 'evidence', 'summary'],
    );
    final directFeedback = _firstNonEmptyString(
      map,
      ['direct_feedback', 'feedback', 'critique'],
    );
    if (key == null || title == null || evidenceSummary == null) {
      return null;
    }
    return AppearanceCandidateConcern(
      id: _intValue(map['id']),
      assessmentId: _intValue(map['assessment_id']),
      concernKey: key,
      domain: _firstNonEmptyString(map, ['domain']) ?? 'general',
      title: title,
      confidence: _doubleValue(map['confidence']) ?? 0.0,
      severity: _firstNonEmptyString(map, ['severity']) ?? 'moderate',
      evidenceSummary: evidenceSummary,
      directFeedback: directFeedback ?? evidenceSummary,
      interventionTier:
          _firstNonEmptyString(map, ['intervention_tier']) ?? 'routine',
      redFlag: _boolValue(map['red_flag']) ?? false,
      sourceIds: _sourceIdList(map['source_ids'] ?? map['sources']),
    );
  }
}

class AppearancePlanStep {
  const AppearancePlanStep({
    required this.phaseKey,
    required this.title,
    required this.cadence,
    required this.durationDays,
    this.actions = const [],
    this.stopConditions = const [],
  });

  final String phaseKey;
  final String title;
  final String cadence;
  final int durationDays;
  final List<String> actions;
  final List<String> stopConditions;

  Map<String, Object?> toJson() {
    return {
      'phase_key': phaseKey,
      'title': title,
      'cadence': cadence,
      'duration_days': durationDays,
      'actions': actions,
      'stop_conditions': stopConditions,
    };
  }

  static List<AppearancePlanStep> listFromDynamic(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    final steps = <AppearancePlanStep>[];
    for (final item in raw) {
      final step = fromDynamic(item);
      if (step != null) {
        steps.add(step);
      }
    }
    return steps;
  }

  static AppearancePlanStep? fromDynamic(dynamic raw) {
    final map = _asStringKeyMap(raw);
    if (map == null) {
      return null;
    }
    final phaseKey = _firstNonEmptyString(map, ['phase_key', 'id', 'key']);
    final title = _firstNonEmptyString(map, ['title', 'label']);
    if (phaseKey == null || title == null) {
      return null;
    }
    return AppearancePlanStep(
      phaseKey: phaseKey,
      title: title,
      cadence: _firstNonEmptyString(map, ['cadence']) ?? 'Daily',
      durationDays: _intValue(map['duration_days']) ?? 14,
      actions: _stringList(map['actions']),
      stopConditions: _stringList(
        map['stop_conditions'] ?? map['stop_rules'],
      ),
    );
  }
}

class AppearanceCarePlan {
  const AppearanceCarePlan({
    this.id,
    this.assessmentId,
    required this.concernKey,
    required this.domain,
    required this.title,
    required this.summary,
    required this.interventionTier,
    required this.currentPhase,
    this.checkpointDays = const [],
    this.escalationRules = const [],
    this.sourceIds = const [],
    this.steps = const [],
    this.active = true,
  });

  final int? id;
  final int? assessmentId;
  final String concernKey;
  final String domain;
  final String title;
  final String summary;
  final String interventionTier;
  final String currentPhase;
  final List<int> checkpointDays;
  final List<String> escalationRules;
  final List<String> sourceIds;
  final List<AppearancePlanStep> steps;
  final bool active;

  Map<String, Object?> toJson() {
    return {
      if (id != null) 'id': id,
      if (assessmentId != null) 'assessment_id': assessmentId,
      'concern_key': concernKey,
      'domain': domain,
      'title': title,
      'summary': summary,
      'intervention_tier': interventionTier,
      'current_phase': currentPhase,
      'checkpoint_days': checkpointDays,
      'escalation_rules': escalationRules,
      'source_ids': sourceIds,
      'steps': [for (final step in steps) step.toJson()],
      'active': active,
    };
  }

  static List<AppearanceCarePlan> listFromDynamic(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    final plans = <AppearanceCarePlan>[];
    for (final item in raw) {
      final plan = fromDynamic(item);
      if (plan != null) {
        plans.add(plan);
      }
    }
    return plans;
  }

  static AppearanceCarePlan? fromDynamic(dynamic raw) {
    final map = _asStringKeyMap(raw);
    if (map == null) {
      return null;
    }
    final concernKey = _firstNonEmptyString(map, ['concern_key', 'key']);
    final title = _firstNonEmptyString(map, ['title']);
    final summary = _firstNonEmptyString(map, ['summary']);
    if (concernKey == null || title == null || summary == null) {
      return null;
    }
    return AppearanceCarePlan(
      id: _intValue(map['id']),
      assessmentId: _intValue(map['assessment_id']),
      concernKey: concernKey,
      domain: _firstNonEmptyString(map, ['domain']) ?? 'general',
      title: title,
      summary: summary,
      interventionTier:
          _firstNonEmptyString(map, ['intervention_tier']) ?? 'routine',
      currentPhase:
          _firstNonEmptyString(map, ['current_phase']) ?? 'baseline_reset',
      checkpointDays: _intList(map['checkpoint_days']),
      escalationRules: _stringList(map['escalation_rules']),
      sourceIds: _sourceIdList(map['source_ids']),
      steps: AppearancePlanStep.listFromDynamic(map['steps']),
      active: _boolValue(map['active']) ?? true,
    );
  }
}

class AppearanceAssessmentResult {
  const AppearanceAssessmentResult({
    this.assessmentId,
    this.imagePath,
    this.questionnaire = const AppearanceQuestionnaire(),
    required this.generatedAt,
    required this.overallSummary,
    required this.directVerdict,
    this.candidateConcerns = const [],
    this.plans = const [],
    this.sourceDocuments = const [],
  });

  final int? assessmentId;
  final String? imagePath;
  final AppearanceQuestionnaire questionnaire;
  final DateTime generatedAt;
  final String overallSummary;
  final String directVerdict;
  final List<AppearanceCandidateConcern> candidateConcerns;
  final List<AppearanceCarePlan> plans;
  final List<AppearanceSourceDocument> sourceDocuments;

  bool get hasRedFlags => candidateConcerns.any((concern) => concern.redFlag);

  List<AppearanceCandidateConcern> get orderedConcerns {
    final concerns = [...candidateConcerns];
    concerns.sort((a, b) {
      final redCompare = (b.redFlag ? 1 : 0).compareTo(a.redFlag ? 1 : 0);
      if (redCompare != 0) {
        return redCompare;
      }
      final severityCompare = _severityRank(b.severity).compareTo(
        _severityRank(a.severity),
      );
      if (severityCompare != 0) {
        return severityCompare;
      }
      return b.confidence.compareTo(a.confidence);
    });
    return concerns;
  }

  Map<String, Object?> toJson() {
    return {
      if (assessmentId != null) 'assessment_id': assessmentId,
      if (imagePath != null && imagePath!.trim().isNotEmpty)
        'image_path': imagePath,
      'questionnaire': questionnaire.toJson(),
      'generated_at': generatedAt.toIso8601String(),
      'overall_summary': overallSummary,
      'direct_verdict': directVerdict,
      'candidate_concerns': [
        for (final concern in candidateConcerns) concern.toJson(),
      ],
      'plans': [for (final plan in plans) plan.toJson()],
      'source_documents': [
        for (final document in sourceDocuments) document.toJson(),
      ],
    };
  }

  static AppearanceAssessmentResult? fromDynamic(dynamic raw) {
    final map = _asStringKeyMap(raw);
    if (map == null) {
      return null;
    }
    final overallSummary = _firstNonEmptyString(
      map,
      ['overall_summary', 'summary'],
    );
    final directVerdict = _firstNonEmptyString(
      map,
      ['direct_verdict', 'verdict'],
    );
    if (overallSummary == null || directVerdict == null) {
      return null;
    }
    return AppearanceAssessmentResult(
      assessmentId: _intValue(map['assessment_id']),
      imagePath: _firstNonEmptyString(map, ['image_path']),
      questionnaire: AppearanceQuestionnaire.fromDynamic(map['questionnaire']),
      generatedAt: _dateTimeValue(map['generated_at']) ?? DateTime.now(),
      overallSummary: overallSummary,
      directVerdict: directVerdict,
      candidateConcerns: AppearanceCandidateConcern.listFromDynamic(
        map['candidate_concerns'] ?? map['concerns'],
      ),
      plans: AppearanceCarePlan.listFromDynamic(map['plans']),
      sourceDocuments: AppearanceSourceDocument.listFromDynamic(
        map['source_documents'] ?? map['sources'],
      ),
    );
  }
}

class AppearanceProgressReview {
  const AppearanceProgressReview({
    required this.id,
    required this.planId,
    required this.createdAt,
    this.planTitle,
    this.adherence,
    this.symptomChange,
    this.sideEffects,
    this.notes,
    this.imagePath,
  });

  final int id;
  final int planId;
  final DateTime createdAt;
  final String? planTitle;
  final int? adherence;
  final String? symptomChange;
  final String? sideEffects;
  final String? notes;
  final String? imagePath;
}

class AppearanceConcernTemplate {
  const AppearanceConcernTemplate({
    required this.key,
    required this.domain,
    required this.label,
    required this.analysisHint,
    required this.planSummary,
    required this.interventionTier,
    required this.checkpointDays,
    required this.escalationRules,
    required this.steps,
    required this.sourceDocuments,
  });

  final String key;
  final String domain;
  final String label;
  final String analysisHint;
  final String planSummary;
  final String interventionTier;
  final List<int> checkpointDays;
  final List<String> escalationRules;
  final List<AppearancePlanStep> steps;
  final List<AppearanceSourceDocument> sourceDocuments;

  AppearanceCandidateConcern buildConcern({
    required double confidence,
    required String severity,
    required String evidenceSummary,
    required String directFeedback,
    required bool redFlag,
  }) {
    return AppearanceCandidateConcern(
      concernKey: key,
      domain: domain,
      title: label,
      confidence: confidence.clamp(0.0, 1.0),
      severity: severity,
      evidenceSummary: evidenceSummary,
      directFeedback: directFeedback,
      interventionTier: interventionTier,
      redFlag: redFlag,
      sourceIds: [
        for (final document in sourceDocuments) document.normalizedId
      ],
    );
  }

  AppearanceCarePlan buildPlan(String directFeedback) {
    return AppearanceCarePlan(
      concernKey: key,
      domain: domain,
      title: label,
      summary: directFeedback.trim().isNotEmpty ? directFeedback : planSummary,
      interventionTier: interventionTier,
      currentPhase: steps.isEmpty ? 'baseline_reset' : steps.first.phaseKey,
      checkpointDays: checkpointDays,
      escalationRules: escalationRules,
      sourceIds: [
        for (final document in sourceDocuments) document.normalizedId
      ],
      steps: steps,
      active: true,
    );
  }
}

class AppearanceProtocolLibrary {
  static const List<String> supportedDomains = [
    'skin',
    'hair',
    'style',
    'physique',
  ];

  static final List<AppearanceConcernTemplate> templates = [
    AppearanceConcernTemplate(
      key: 'acne_activity',
      domain: 'skin',
      label: 'Active acne pressure',
      analysisHint:
          'Use when the photo or questionnaire suggests visible breakouts, clogged pores, inflamed spots, or repeated acne flares.',
      planSummary:
          'The skin needs oil-control and irritation-control work, not random product stacking. Build a basic acne-safe routine first, then escalate deliberately if inflammation or scarring risk stays high.',
      interventionTier: 'clinician',
      checkpointDays: [14, 42, 84],
      escalationRules: const [
        'Escalate to a dermatologist if cystic lesions, scarring, or widespread inflammation are present.',
        'Escalate if the skin is worsening after a careful 6 to 8 week OTC trial.',
      ],
      steps: const [
        AppearancePlanStep(
          phaseKey: 'baseline_reset',
          title: 'Baseline reset',
          cadence: 'Morning and evening',
          durationDays: 14,
          actions: [
            'Use a gentle cleanser, non-comedogenic moisturizer, and daily broad-spectrum sunscreen.',
            'Stop harsh scrubs and random overlapping actives.',
            'Track lesion count, oiliness, and irritation with baseline photos.',
          ],
          stopConditions: [
            'Stop any product that causes marked burning, swelling, or rash.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'otc_trial',
          title: 'OTC treatment trial',
          cadence: 'Daily with gradual tolerance ramp',
          durationDays: 28,
          actions: [
            'Introduce one acne-active at a time and keep the rest of the routine simple.',
            'Prioritize consistency over adding extra products.',
            'Keep sunscreen and barrier support in place to limit rebound irritation and dark marks.',
          ],
          stopConditions: [
            'Pause the active and reset the barrier if peeling or burning becomes hard to control.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'clinician_escalation',
          title: 'Clinician escalation',
          cadence: 'Consult-driven',
          durationDays: 30,
          actions: [
            'Discuss prescription options with a dermatologist if inflammatory acne persists.',
            'Ask about scar prevention if lesions are deep, painful, or repeatedly picked.',
          ],
          stopConditions: [
            'Do not self-prescribe oral or hormonal treatment.',
          ],
        ),
      ],
      sourceDocuments: [
        AppearanceSourceDocument(
          id: 'AAD_ACNE_2024',
          domain: 'skin',
          title: 'AAD acne management guidance',
          citation:
              'American Academy of Dermatology. Updated guidance for acne management.',
          url: 'https://www.aad.org/news/updated-guidelines-acne-management',
          rationale:
              'Used for conservative acne treatment sequencing and escalation boundaries.',
        ),
        AppearanceSourceDocument(
          id: 'AAD_ACNE_RESOURCE',
          domain: 'skin',
          title: 'AAD Acne Resource Center',
          citation: 'American Academy of Dermatology. Acne Resource Center.',
          url: 'https://www.aad.org/diseases/acne',
          rationale:
              'Supports acne-safe skin care and darker-skin hyperpigmentation context.',
        ),
      ],
    ),
    AppearanceConcernTemplate(
      key: 'hyperpigmentation_tone',
      domain: 'skin',
      label: 'Uneven tone and dark-mark carryover',
      analysisHint:
          'Use when the main issue is post-acne marks, uneven tone, or dark patches rather than active inflammatory breakouts.',
      planSummary:
          'The bottleneck is pigment carryover and UV or irritation control. The cycle should focus on sunscreen discipline, gentle products, and avoiding irritation that keeps creating new marks.',
      interventionTier: 'procedure',
      checkpointDays: [21, 56, 112],
      escalationRules: const [
        'Escalate if discoloration is rapidly changing, patchy in an unusual pattern, or paired with significant irritation.',
        'Procedure-tier options should be discussed with a dermatologist rather than trialed casually.',
      ],
      steps: const [
        AppearancePlanStep(
          phaseKey: 'photoprotection_lock',
          title: 'Photoprotection lock-in',
          cadence: 'Daily',
          durationDays: 21,
          actions: [
            'Use broad-spectrum SPF 30 or higher every day and reapply when exposure is prolonged.',
            'Reduce friction and irritation from harsh exfoliation or aggressive picking.',
          ],
          stopConditions: [
            'Stop any product that stings or burns consistently.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'tone_evening_cycle',
          title: 'Tone-evening cycle',
          cadence: 'Daily with slow ramp',
          durationDays: 35,
          actions: [
            'Keep the routine boring and stable so new marks stop forming.',
            'Track the oldest and darkest patches with repeat photos in similar lighting.',
          ],
          stopConditions: [
            'Pause the cycle if irritation is outpacing improvement.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'procedure_consult',
          title: 'Procedure consult gate',
          cadence: 'As needed',
          durationDays: 30,
          actions: [
            'Discuss dermatologist-guided options for persistent marks that are not improving with conservative care.',
          ],
          stopConditions: [
            'Do not improvise bleach, harsh peels, or off-label DIY procedures.',
          ],
        ),
      ],
      sourceDocuments: [
        AppearanceSourceDocument(
          id: 'AAD_HYPERPIGMENTATION',
          domain: 'skin',
          title: 'AAD guidance on fading dark spots',
          citation:
              'American Academy of Dermatology. Guidance on fading dark spots and protecting against visible light.',
          url:
              'https://www.aad.org/stories-and-news/news-releases/dermatologist-shines-light-on-natural-ingredients-used-in-new-topical-treatments-for-hyperpigmentation',
          rationale:
              'Supports sunscreen-first and anti-irritation guidance for dark-mark control.',
        ),
      ],
    ),
    AppearanceConcernTemplate(
      key: 'barrier_irritation_dryness',
      domain: 'skin',
      label: 'Barrier irritation and dryness',
      analysisHint:
          'Use when the skin appears dry, inflamed, over-exfoliated, flaky, or when the questionnaire describes tightness, stinging, or frequent product irritation.',
      planSummary:
          'The skin barrier looks overworked. The treatment cycle should reduce inputs, remove avoidable irritants, and rebuild tolerance before any aggressive actives return.',
      interventionTier: 'routine',
      checkpointDays: [7, 21, 42],
      escalationRules: const [
        'Escalate if rash, swelling, crusting, or persistent pain is present.',
      ],
      steps: const [
        AppearancePlanStep(
          phaseKey: 'input_reduction',
          title: 'Input reduction',
          cadence: 'Daily',
          durationDays: 7,
          actions: [
            'Strip the routine down to gentle cleanser, moisturizer, and sunscreen.',
            'Pause fragrance-heavy, alcohol-heavy, or strongly exfoliating products.',
          ],
          stopConditions: [
            'Stop products that trigger obvious burning or rash.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'barrier_rebuild',
          title: 'Barrier rebuild',
          cadence: 'Daily',
          durationDays: 21,
          actions: [
            'Keep the routine simple and fragrance-free until stinging and tightness settle.',
            'Reintroduce one active at a time only after the skin is stable.',
          ],
          stopConditions: [
            'Do not stack actives while the barrier is still irritated.',
          ],
        ),
      ],
      sourceDocuments: [
        AppearanceSourceDocument(
          id: 'AAD_DRY_SKIN_RELIEF',
          domain: 'skin',
          title: 'AAD dry skin relief guidance',
          citation:
              "American Academy of Dermatology. Dermatologists' top tips for relieving dry skin.",
          url:
              'https://www.aad.org/public/skin-hair-nails/skin-care/dry-skin-relief',
          rationale:
              'Supports fragrance-free, irritation-reduction, and barrier-first guidance.',
        ),
      ],
    ),
    AppearanceConcernTemplate(
      key: 'dandruff_flaking',
      domain: 'hair',
      label: 'Scalp flaking and dandruff pressure',
      analysisHint:
          'Use when the scalp shows flaking or the questionnaire reports dandruff, itchy scalp, or seborrheic dermatitis-type symptoms.',
      planSummary:
          'The scalp needs a controlled dandruff cycle rather than cosmetic cover-ups. Start with directed shampoo use and scalp hygiene, then escalate if flakes and itch stay active.',
      interventionTier: 'clinician',
      checkpointDays: [14, 28, 56],
      escalationRules: const [
        'Escalate if thick scale, marked redness, bleeding, or no improvement after a careful OTC trial is present.',
      ],
      steps: const [
        AppearancePlanStep(
          phaseKey: 'scalp_control',
          title: 'Scalp control',
          cadence: '1 to 3 times weekly based on hair type',
          durationDays: 14,
          actions: [
            'Use a dandruff shampoo as directed and give it time to sit on the scalp.',
            'Match wash frequency to scalp oil and hair texture instead of guessing.',
          ],
          stopConditions: [
            'Stop if the scalp becomes sharply more irritated or painful.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'maintenance_rotation',
          title: 'Maintenance rotation',
          cadence: 'Weekly maintenance',
          durationDays: 28,
          actions: [
            'Rotate products if one shampoo loses effectiveness.',
            'Track itch, flaking, and visible scale in repeat scalp photos.',
          ],
          stopConditions: [
            'Do not over-scratch or pick at plaques.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'clinician_escalation',
          title: 'Clinician escalation',
          cadence: 'Consult-driven',
          durationDays: 30,
          actions: [
            'Discuss prescription shampoo or topical treatment if the scalp remains active.',
          ],
          stopConditions: [
            'Do not improvise steroid use without clinician guidance.',
          ],
        ),
      ],
      sourceDocuments: [
        AppearanceSourceDocument(
          id: 'AAD_SEBORRHEIC_TREATMENT',
          domain: 'hair',
          title: 'AAD seborrheic dermatitis diagnosis and treatment',
          citation:
              'American Academy of Dermatology. Seborrheic dermatitis: Diagnosis and treatment.',
          url:
              'https://www.aad.org/public/diseases/a-z/seborrheic-dermatitis-treatment',
          rationale:
              'Supports dandruff shampoo use, prescription escalation, and maintenance framing.',
        ),
        AppearanceSourceDocument(
          id: 'AAD_DANDRUFF_TIPS',
          domain: 'hair',
          title: 'AAD dandruff home-care guidance',
          citation: 'American Academy of Dermatology. How to treat dandruff.',
          url: 'https://www.aad.org/hair-scalp-care/treat-dandruff',
          rationale:
              'Supports OTC shampoo selection and hair-type-specific wash cadence.',
        ),
      ],
    ),
    AppearanceConcernTemplate(
      key: 'hair_thinning_recession',
      domain: 'hair',
      label: 'Hair thinning or recession',
      analysisHint:
          'Use when there is visible recession, diffuse thinning, or the questionnaire reports unusual shedding or density loss.',
      planSummary:
          'Density loss is a high-leverage appearance issue and it rewards early action. Baseline it fast, clean up damaging habits, and escalate to clinician-guided treatment instead of hoping it self-corrects.',
      interventionTier: 'procedure',
      checkpointDays: [14, 42, 90],
      escalationRules: const [
        'Escalate promptly if shedding is abrupt, patchy, or paired with scalp inflammation.',
        'Clinician-guided treatment is the default for persistent thinning or recession.',
      ],
      steps: const [
        AppearancePlanStep(
          phaseKey: 'baseline_density',
          title: 'Density baseline',
          cadence: 'Weekly review',
          durationDays: 14,
          actions: [
            'Capture repeat photos of the hairline, crown, and part under similar lighting.',
            'Reduce traction, heat, and breakage-heavy styling while you baseline the issue.',
          ],
          stopConditions: [
            'Do not ignore sudden shedding or scalp pain.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'damage_control',
          title: 'Damage control',
          cadence: 'Daily and weekly',
          durationDays: 28,
          actions: [
            'Prioritize gentle washing, conditioning, and lower-tension styling.',
            'Keep routines consistent enough to distinguish breakage from true density loss.',
          ],
          stopConditions: [
            'Stop tight styles that are increasing tension or breakage.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'clinician_path',
          title: 'Clinician treatment path',
          cadence: 'Consult-driven',
          durationDays: 60,
          actions: [
            'Discuss evidence-based hair-loss treatment options with a dermatologist early.',
            'Use the baseline photo set to judge whether the issue is stabilizing or still slipping.',
          ],
          stopConditions: [
            'Do not self-prescribe systemic or procedural hair-loss treatment.',
          ],
        ),
      ],
      sourceDocuments: [
        AppearanceSourceDocument(
          id: 'AAD_HAIR_LOSS_RESOURCE',
          domain: 'hair',
          title: 'AAD Hair Loss Resource Center',
          citation:
              'American Academy of Dermatology. Hair Loss Resource Center.',
          url:
              'https://www.aad.org/dermatology-a-to-z/diseases-and-treatments/e---h/hair-loss',
          rationale:
              'Supports dermatologist escalation and condition-oriented hair-loss review.',
        ),
        AppearanceSourceDocument(
          id: 'AAD_HAIR_LOSS_TIPS',
          domain: 'hair',
          title: 'AAD hair loss care tips',
          citation:
              'American Academy of Dermatology. Hair loss: Tips for managing.',
          url:
              'https://www.aad.org/public/diseases/hair-and-scalp-problems/hair-loss/',
          rationale:
              'Supports conservative handling of fragile hair and early specialist escalation.',
        ),
      ],
    ),
    AppearanceConcernTemplate(
      key: 'hair_breakage_damage',
      domain: 'hair',
      label: 'Breakage and cosmetic hair damage',
      analysisHint:
          'Use when the hair looks brittle or the questionnaire emphasizes dryness, breakage, heat damage, or traction-heavy styling.',
      planSummary:
          'The hair is taking avoidable mechanical or heat damage. The cycle is about reducing destructive styling habits and restoring basic conditioning discipline before chasing cosmetic tricks.',
      interventionTier: 'routine',
      checkpointDays: [14, 42],
      escalationRules: const [
        'Escalate if breakage reduction does not stabilize density or if scalp pain accompanies styling.',
      ],
      steps: const [
        AppearancePlanStep(
          phaseKey: 'damage_stop',
          title: 'Damage stop',
          cadence: 'Daily habit reset',
          durationDays: 14,
          actions: [
            'Reduce hot-tool use, tight styles, and aggressive brushing.',
            'Use conditioner consistently and handle wet hair gently.',
          ],
          stopConditions: [
            'Stop routines that visibly increase shedding or breakage.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'protective_maintenance',
          title: 'Protective maintenance',
          cadence: 'Weekly review',
          durationDays: 28,
          actions: [
            'Keep heat low, tension low, and styling simple while the hair recovers.',
            'Track split ends, frizz, and snap-prone areas in repeat photos.',
          ],
          stopConditions: [
            'Do not keep stacking chemical services close together.',
          ],
        ),
      ],
      sourceDocuments: [
        AppearanceSourceDocument(
          id: 'AAD_HAIR_DAMAGE',
          domain: 'hair',
          title: 'AAD hair-damage prevention guidance',
          citation:
              'American Academy of Dermatology. How to stop damaging your hair.',
          url:
              'https://www.aad.org/public/skin-hair-nails/hair-care/how-to-stop-hair-damage',
          rationale:
              'Supports low-tension, low-heat, conditioning, and breakage-reduction guidance.',
        ),
        AppearanceSourceDocument(
          id: 'AAD_HAIR_STYLING',
          domain: 'hair',
          title: 'AAD styling without damage guidance',
          citation:
              'American Academy of Dermatology. Hair styling without damage.',
          url:
              'https://www.aad.org/public/skin-hair-nails/hair-care/hair-styling-without-damage',
          rationale: 'Supports safer styling cadence and traction boundaries.',
        ),
      ],
    ),
    AppearanceConcernTemplate(
      key: 'grooming_inconsistency',
      domain: 'style',
      label: 'Grooming inconsistency',
      analysisHint:
          'Use when overall presentation is being dragged down by inconsistent beard, brow, nail, scent, or maintenance discipline rather than a skin or hair disorder.',
      planSummary:
          'The issue is maintenance discipline, not genetics. Build a repeatable grooming cycle so the presentation stops fluctuating.',
      interventionTier: 'routine',
      checkpointDays: [7, 21],
      escalationRules: const [
        'Escalate to a barber, stylist, or dermatologist if grooming issues are being driven by skin or scalp symptoms.',
      ],
      steps: const [
        AppearancePlanStep(
          phaseKey: 'weekly_standard',
          title: 'Weekly standard',
          cadence: 'Daily and weekly',
          durationDays: 14,
          actions: [
            'Set a fixed cadence for beard cleanup, nail maintenance, and hairline or neckline cleanup.',
            'Keep products minimal and functional instead of chasing novelty.',
          ],
          stopConditions: [
            'Stop any grooming step that is irritating skin repeatedly.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'consistency_lock',
          title: 'Consistency lock',
          cadence: 'Weekly review',
          durationDays: 21,
          actions: [
            'Use repeat photos to judge whether presentation is tightening up from week to week.',
            'Remove low-value grooming steps that cost time without improving presentation.',
          ],
          stopConditions: [
            'Do not add extra complexity until the baseline cycle is stable.',
          ],
        ),
      ],
      sourceDocuments: const [
        AppearanceSourceDocument(
          id: 'ORA_STYLE_POLICY',
          domain: 'style',
          title: 'Ora appearance optimization policy',
          citation:
              'Ora internal policy for consistent grooming, fit, and presentation review.',
          rationale:
              'Used for non-medical grooming standards where a local operational policy is more appropriate than a medical source.',
        ),
      ],
    ),
    AppearanceConcernTemplate(
      key: 'style_fit_coordination',
      domain: 'style',
      label: 'Weak fit and coordination',
      analysisHint:
          'Use when outfit structure, fit, coordination, or silhouette is clearly weakening overall presentation.',
      planSummary:
          'The bottleneck is presentation engineering. Tighten fit, reduce visual clutter, and make the silhouette look deliberate instead of accidental.',
      interventionTier: 'routine',
      checkpointDays: [7, 21, 42],
      escalationRules: const [
        'Escalate to a stylist or tailor if repeated wardrobe changes are still producing weak structure.',
      ],
      steps: const [
        AppearancePlanStep(
          phaseKey: 'closet_audit',
          title: 'Closet audit',
          cadence: 'One focused pass',
          durationDays: 7,
          actions: [
            'Remove the worst-fit items from the primary rotation.',
            'Identify one reliable silhouette for casual, gym, and going-out contexts.',
          ],
          stopConditions: [
            'Stop buying trend items before the basics fit correctly.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'uniform_build',
          title: 'Uniform build',
          cadence: 'Weekly refinement',
          durationDays: 21,
          actions: [
            'Standardize color coordination and shoe quality around a smaller set of reliable combinations.',
            'Use photos to compare good-fit vs bad-fit outfits side by side.',
          ],
          stopConditions: [
            'Do not solve fit problems with oversized layering or visual noise.',
          ],
        ),
      ],
      sourceDocuments: const [
        AppearanceSourceDocument(
          id: 'ORA_STYLE_UNIFORM',
          domain: 'style',
          title: 'Ora style uniform standard',
          citation:
              'Ora internal guidance on fit, silhouette, and repeatable wardrobe structure.',
          rationale: 'Used for non-medical style optimization decisions.',
        ),
      ],
    ),
    AppearanceConcernTemplate(
      key: 'posture_presence',
      domain: 'physique',
      label: 'Posture and presence leakage',
      analysisHint:
          'Use when posture, shoulder positioning, or general body presentation is visibly weakening overall appearance.',
      planSummary:
          'The frame is leaking presence through posture and baseline movement quality. Fixing that can improve appearance quickly without pretending it replaces long-term physique work.',
      interventionTier: 'routine',
      checkpointDays: [14, 42],
      escalationRules: const [
        'Escalate to a clinician or physio if pain, asymmetry, or movement limitation is driving the posture issue.',
      ],
      steps: const [
        AppearancePlanStep(
          phaseKey: 'position_reset',
          title: 'Position reset',
          cadence: 'Daily',
          durationDays: 14,
          actions: [
            'Use repeat front and side photos to build posture awareness.',
            'Add short daily work for upper-back engagement, ribcage stacking, and neck position control.',
          ],
          stopConditions: [
            'Stop any drill that produces pain rather than simple fatigue or effort.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'carryover',
          title: 'Carryover into daily movement',
          cadence: 'Daily and training days',
          durationDays: 28,
          actions: [
            'Carry the new posture into walking, sitting, and gym setup instead of treating it as one drill block.',
          ],
          stopConditions: [
            'Do not force rigid military posture that creates tension everywhere else.',
          ],
        ),
      ],
      sourceDocuments: [
        AppearanceSourceDocument(
          id: 'HHS_PHYSICAL_ACTIVITY_2018',
          domain: 'physique',
          title: 'Physical Activity Guidelines for Americans',
          citation:
              'U.S. Department of Health and Human Services. Physical Activity Guidelines for Americans, 2nd edition.',
          url: 'https://stacks.cdc.gov/view/cdc/121857',
          rationale:
              'Supports baseline activity and strengthening guidance for posture and general physical presentation.',
        ),
      ],
    ),
    AppearanceConcernTemplate(
      key: 'definition_muscularity',
      domain: 'physique',
      label: 'Definition and muscularity gap',
      analysisHint:
          'Use when body composition, musculature, or general physique development is a visible bottleneck for the users stated goals.',
      planSummary:
          'The frame likely needs either more muscle, less fat, or both. The cycle should focus on sustainable training and nutrition discipline rather than cosmetic shortcuts.',
      interventionTier: 'routine',
      checkpointDays: [14, 42, 84],
      escalationRules: const [
        'Escalate to a clinician if weight change pressure is pairing with extreme restriction, supplements abuse, or health symptoms.',
      ],
      steps: const [
        AppearancePlanStep(
          phaseKey: 'baseline_capture',
          title: 'Baseline capture',
          cadence: 'Weekly',
          durationDays: 14,
          actions: [
            'Track repeat body photos, waist trend, and training consistency before overreacting.',
            'Pick one primary target: cut noise, build size, or improve posture and presentation first.',
          ],
          stopConditions: [
            'Do not change training and diet variables all at once.',
          ],
        ),
        AppearancePlanStep(
          phaseKey: 'training_nutrition_block',
          title: 'Training and nutrition block',
          cadence: 'Weekly programming block',
          durationDays: 56,
          actions: [
            'Match nutrition and training to the chosen physique objective and keep it stable long enough to evaluate.',
            'Use progressive overload and recovery discipline instead of chasing novelty.',
          ],
          stopConditions: [
            'Stop using crash-diet or overtraining behavior as an appearance strategy.',
          ],
        ),
      ],
      sourceDocuments: [
        AppearanceSourceDocument(
          id: 'HHS_PHYSICAL_ACTIVITY_2018',
          domain: 'physique',
          title: 'Physical Activity Guidelines for Americans',
          citation:
              'U.S. Department of Health and Human Services. Physical Activity Guidelines for Americans, 2nd edition.',
          url: 'https://stacks.cdc.gov/view/cdc/121857',
          rationale:
              'Supports baseline strength and activity guidance for physique change.',
        ),
      ],
    ),
  ];

  static String taxonomyPrompt() {
    final buffer = StringBuffer();
    for (final template in templates) {
      buffer.writeln(
          '- ${template.key} [${template.domain}] ${template.label}: ${template.analysisHint}');
    }
    return buffer.toString().trimRight();
  }

  static AppearanceConcernTemplate? templateForKey(String key) {
    final normalized = key.trim().toLowerCase();
    for (final template in templates) {
      if (template.key == normalized) {
        return template;
      }
    }
    return null;
  }

  static List<AppearanceCarePlan> buildPlans(
    Iterable<AppearanceCandidateConcern> concerns,
  ) {
    final plans = <AppearanceCarePlan>[];
    final seen = <String>{};
    for (final concern in concerns) {
      final template = templateForKey(concern.concernKey);
      if (template == null) {
        continue;
      }
      if (!seen.add(template.key)) {
        continue;
      }
      plans.add(template.buildPlan(concern.directFeedback));
    }
    return plans;
  }

  static List<AppearanceSourceDocument> collectSources(
    Iterable<AppearanceCarePlan> plans,
  ) {
    final documents = <AppearanceSourceDocument>[];
    final seen = <String>{};
    for (final plan in plans) {
      final template = templateForKey(plan.concernKey);
      if (template == null) {
        continue;
      }
      for (final document in template.sourceDocuments) {
        if (seen.add(document.normalizedId)) {
          documents.add(document);
        }
      }
    }
    return documents;
  }

  static AppearanceAssessmentResult applyTemplates({
    required DateTime generatedAt,
    required String overallSummary,
    required String directVerdict,
    required List<AppearanceCandidateConcern> concerns,
  }) {
    final plans = buildPlans(concerns.where((concern) => !concern.redFlag));
    final sources = collectSources(plans);
    return AppearanceAssessmentResult(
      generatedAt: generatedAt,
      overallSummary: overallSummary,
      directVerdict: directVerdict,
      candidateConcerns: concerns,
      plans: plans,
      sourceDocuments: sources,
    );
  }
}

Map<String, dynamic>? _asStringKeyMap(dynamic raw) {
  if (raw is Map) {
    final map = <String, dynamic>{};
    raw.forEach((key, value) {
      map[key.toString()] = value;
    });
    return map;
  }
  return null;
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

List<String> _stringList(dynamic raw) {
  if (raw is List) {
    return [
      for (final item in raw)
        if (item != null && item.toString().trim().isNotEmpty)
          item.toString().trim(),
    ];
  }
  if (raw == null) {
    return const [];
  }
  final text = raw.toString().trim();
  if (text.isEmpty) {
    return const [];
  }
  return [text];
}

List<int> _intList(dynamic raw) {
  if (raw is! List) {
    return const [];
  }
  final values = <int>[];
  for (final item in raw) {
    final value = _intValue(item);
    if (value != null) {
      values.add(value);
    }
  }
  return values;
}

List<String> _sourceIdList(dynamic raw) {
  return _stringList(raw).map(_normalizeSourceId).toList();
}

String _normalizeSourceId(String raw) {
  final text = raw.trim().toUpperCase().replaceAll(' ', '');
  return text.isEmpty ? 'SRC1' : text;
}

int? _intValue(dynamic raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is double) {
    return raw.round();
  }
  return int.tryParse(raw?.toString() ?? '');
}

double? _doubleValue(dynamic raw) {
  if (raw is double) {
    return raw;
  }
  if (raw is int) {
    return raw.toDouble();
  }
  return double.tryParse(raw?.toString() ?? '');
}

bool? _boolValue(dynamic raw) {
  if (raw is bool) {
    return raw;
  }
  if (raw is int) {
    return raw != 0;
  }
  final text = raw?.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') {
    return true;
  }
  if (text == 'false' || text == '0' || text == 'no') {
    return false;
  }
  return null;
}

DateTime? _dateTimeValue(dynamic raw) {
  if (raw == null) {
    return null;
  }
  return DateTime.tryParse(raw.toString());
}

int _severityRank(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'high':
      return 3;
    case 'moderate':
      return 2;
    case 'low':
    default:
      return 1;
  }
}
