List<String> migration0012() {
  return [
    "ALTER TABLE set_entry ADD COLUMN set_tag TEXT NOT NULL DEFAULT 'normal';",
    'ALTER TABLE session_exercise ADD COLUMN superset_group_id INTEGER;',
    'ALTER TABLE program_day_exercise ADD COLUMN superset_group_id INTEGER;',
  ];
}
