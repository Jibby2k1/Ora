List<String> migration0010() {
  return [
    'ALTER TABLE diet_entry ADD COLUMN barcode TEXT;',
    'ALTER TABLE diet_entry ADD COLUMN food_source TEXT;',
    'ALTER TABLE diet_entry ADD COLUMN food_source_id TEXT;',
    'ALTER TABLE diet_entry ADD COLUMN portion_label TEXT;',
    'ALTER TABLE diet_entry ADD COLUMN portion_grams REAL;',
    'ALTER TABLE diet_entry ADD COLUMN portion_amount REAL;',
    'ALTER TABLE diet_entry ADD COLUMN portion_unit TEXT;',
    "ALTER TABLE diet_entry ADD COLUMN meal_type TEXT NOT NULL DEFAULT 'snack';",
    '''
UPDATE diet_entry
SET meal_type = CASE
  WHEN CAST(substr(logged_at, 12, 2) AS INTEGER) BETWEEN 5 AND 10 THEN 'breakfast'
  WHEN CAST(substr(logged_at, 12, 2) AS INTEGER) BETWEEN 11 AND 15 THEN 'lunch'
  WHEN CAST(substr(logged_at, 12, 2) AS INTEGER) BETWEEN 16 AND 21 THEN 'dinner'
  ELSE 'snack'
END
WHERE meal_type IS NULL OR trim(meal_type) = '';
''',
    'CREATE INDEX IF NOT EXISTS idx_diet_entry_logged_at_meal_type ON diet_entry(logged_at, meal_type);',
  ];
}
