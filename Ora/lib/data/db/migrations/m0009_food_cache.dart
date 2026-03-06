import '../schema.dart';

List<String> migration0009() {
  return [
    createTableFoodCache,
    'CREATE INDEX IF NOT EXISTS idx_food_cache_expires ON food_cache(expires_at);',
  ];
}
