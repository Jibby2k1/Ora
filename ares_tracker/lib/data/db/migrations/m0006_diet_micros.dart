import '../schema.dart';

List<String> migration0006() {
  return [
    'ALTER TABLE diet_entry ADD COLUMN micros_json TEXT;',
  ];
}
