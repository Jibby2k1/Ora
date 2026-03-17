List<String> migration0011() {
  return [
    '''
CREATE TABLE IF NOT EXISTS recipe(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  notes TEXT,
  category TEXT NOT NULL DEFAULT 'meal',
  servings REAL NOT NULL DEFAULT 1,
  is_favorite INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''',
    '''
CREATE TABLE IF NOT EXISTS recipe_ingredient(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  recipe_id INTEGER NOT NULL,
  order_index INTEGER NOT NULL,
  food_id TEXT NOT NULL,
  food_source TEXT NOT NULL,
  food_name TEXT NOT NULL,
  food_json TEXT NOT NULL,
  serving_choice_id TEXT NOT NULL,
  serving_label TEXT NOT NULL,
  serving_unit TEXT,
  serving_gram_weight REAL,
  amount REAL NOT NULL,
  is_approximate INTEGER NOT NULL DEFAULT 0,
  nutrients_json TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(recipe_id) REFERENCES recipe(id)
);
''',
    'CREATE INDEX IF NOT EXISTS idx_recipe_updated_at ON recipe(updated_at DESC);',
    'CREATE INDEX IF NOT EXISTS idx_recipe_ingredient_recipe_order ON recipe_ingredient(recipe_id, order_index);',
  ];
}
