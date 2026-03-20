List<String> migration0013() {
  return [
    '''
CREATE TABLE IF NOT EXISTS exercise_science_info(
  exercise_id INTEGER PRIMARY KEY,
  instructions_json TEXT NOT NULL,
  avoid_json TEXT NOT NULL,
  citations_json TEXT NOT NULL,
  visual_asset_paths_json TEXT NOT NULL,
  FOREIGN KEY(exercise_id) REFERENCES exercise(id)
);
''',
    "ALTER TABLE set_entry ADD COLUMN set_tag TEXT NOT NULL DEFAULT 'normal';",
    'ALTER TABLE session_exercise ADD COLUMN superset_group_id INTEGER;',
    'ALTER TABLE program_day_exercise ADD COLUMN superset_group_id INTEGER;',
  ];
}
