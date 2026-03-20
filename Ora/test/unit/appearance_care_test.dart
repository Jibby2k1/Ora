import 'package:flutter_test/flutter_test.dart';

import 'package:ora/domain/models/appearance_care.dart';

void main() {
  test('questionnaire parsing normalizes alternate keys', () {
    final questionnaire = AppearanceQuestionnaire.fromDynamic({
      'domains': ['skin', 'hair'],
      'diagnoses': ['Acne vulgaris'],
      'concerns': ['breakouts', 'flaking'],
      'symptoms': ['itching'],
      'goals': ['clearer skin'],
      'routine': 'Cleanser and sunscreen',
      'grooming_context': 'Office and gym',
      'sex': 'male',
    });

    expect(questionnaire.domains, ['skin', 'hair']);
    expect(questionnaire.diagnosedConditions, ['Acne vulgaris']);
    expect(questionnaire.mainConcerns, ['breakouts', 'flaking']);
    expect(questionnaire.currentRoutine, 'Cleanser and sunscreen');
    expect(questionnaire.styleContext, 'Office and gym');
    expect(questionnaire.profileSex, 'male');
    expect(questionnaire.hasContent, isTrue);
  });

  test('applyTemplates builds constrained plans and deduplicated sources', () {
    final acne = AppearanceProtocolLibrary.templateForKey('acne_activity')!;
    final thinning = AppearanceProtocolLibrary.templateForKey(
      'hair_thinning_recession',
    )!;
    final redFlag = AppearanceProtocolLibrary.templateForKey(
      'barrier_irritation_dryness',
    )!;

    final result = AppearanceProtocolLibrary.applyTemplates(
      generatedAt: DateTime.parse('2026-03-20T12:00:00Z'),
      overallSummary:
          'Several high-leverage appearance bottlenecks are active.',
      directVerdict:
          'Fix the skin and density issues first, then tighten presentation.',
      concerns: [
        acne.buildConcern(
          confidence: 0.82,
          severity: 'moderate',
          evidenceSummary: 'Inflamed breakouts and oiliness are visible.',
          directFeedback:
              'Build a simple acne-safe cycle before stacking products.',
          redFlag: false,
        ),
        thinning.buildConcern(
          confidence: 0.74,
          severity: 'high',
          evidenceSummary: 'Density loss is visible at the hairline.',
          directFeedback: 'Baseline the hairline now and escalate early.',
          redFlag: false,
        ),
        redFlag.buildConcern(
          confidence: 0.91,
          severity: 'high',
          evidenceSummary: 'The barrier looks inflamed and reactive.',
          directFeedback: 'Stop the aggressive routine and calm the skin down.',
          redFlag: true,
        ),
      ],
    );

    expect(result.plans.map((plan) => plan.concernKey).toList(), [
      'acne_activity',
      'hair_thinning_recession',
    ]);
    expect(result.plans.every((plan) => plan.active), isTrue);
    expect(
      result.plans.first.interventionTier,
      'clinician',
    );
    expect(
      result.plans[1].interventionTier,
      'procedure',
    );
    expect(result.sourceDocuments, isNotEmpty);
    expect(
      result.sourceDocuments
          .map((source) => source.normalizedId)
          .toSet()
          .length,
      result.sourceDocuments.length,
    );
    expect(result.hasRedFlags, isTrue);
  });

  test(
      'assessment ordering prioritizes red flags then severity then confidence',
      () {
    final routine = AppearanceProtocolLibrary.templateForKey(
      'grooming_inconsistency',
    )!;
    final physique = AppearanceProtocolLibrary.templateForKey(
      'definition_muscularity',
    )!;
    final style = AppearanceProtocolLibrary.templateForKey(
      'style_fit_coordination',
    )!;

    final assessment = AppearanceAssessmentResult(
      generatedAt: DateTime.parse('2026-03-20T12:00:00Z'),
      overallSummary: 'Three separate appearance issues were detected.',
      directVerdict: 'Address the acute issue first.',
      candidateConcerns: [
        routine.buildConcern(
          confidence: 0.95,
          severity: 'low',
          evidenceSummary: 'Maintenance is inconsistent.',
          directFeedback: 'Standardize the grooming cadence.',
          redFlag: false,
        ),
        physique.buildConcern(
          confidence: 0.55,
          severity: 'high',
          evidenceSummary: 'Physique development is lagging the stated goal.',
          directFeedback: 'Pick one training objective and hold it steady.',
          redFlag: false,
        ),
        style.buildConcern(
          confidence: 0.40,
          severity: 'low',
          evidenceSummary: 'The fit is weak and presentation is leaking.',
          directFeedback: 'A red-flag style issue is active.',
          redFlag: true,
        ),
      ],
    );

    expect(
      assessment.orderedConcerns.map((concern) => concern.concernKey).toList(),
      [
        'style_fit_coordination',
        'definition_muscularity',
        'grooming_inconsistency'
      ],
    );
  });
}
