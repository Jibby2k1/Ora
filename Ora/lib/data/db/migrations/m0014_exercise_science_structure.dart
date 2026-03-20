List<String> migration0014() {
  return [
    '''
CREATE TABLE IF NOT EXISTS exercise_science_info(
  exercise_id INTEGER PRIMARY KEY,
  instructions_json TEXT NOT NULL,
  avoid_json TEXT NOT NULL,
  citations_json TEXT NOT NULL,
  visual_asset_paths_json TEXT NOT NULL,
  info_sections_json TEXT NOT NULL DEFAULT '[]',
  source_documents_json TEXT NOT NULL DEFAULT '[]',
  FOREIGN KEY(exercise_id) REFERENCES exercise(id)
);
''',
    "ALTER TABLE exercise_science_info ADD COLUMN info_sections_json TEXT NOT NULL DEFAULT '[]';",
    "ALTER TABLE exercise_science_info ADD COLUMN source_documents_json TEXT NOT NULL DEFAULT '[]';",
  ];
}
