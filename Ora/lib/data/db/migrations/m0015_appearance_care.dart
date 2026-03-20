import '../schema.dart';

List<String> migration0015() {
  return [
    createTableAppearanceAssessment,
    createTableAppearanceConcern,
    createTableAppearancePlan,
    createTableAppearancePlanStep,
    createTableAppearanceReview,
    createTableAppearanceSourceDocument,
    'CREATE INDEX IF NOT EXISTS idx_appearance_concern_assessment ON appearance_concern(assessment_id);',
    'CREATE INDEX IF NOT EXISTS idx_appearance_plan_assessment ON appearance_plan(assessment_id);',
    'CREATE INDEX IF NOT EXISTS idx_appearance_plan_active_created ON appearance_plan(is_active, created_at DESC);',
    'CREATE INDEX IF NOT EXISTS idx_appearance_review_plan_created ON appearance_review(plan_id, created_at DESC);',
  ];
}
