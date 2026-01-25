List<String> migration0007() {
  return [
    'ALTER TABLE diet_entry ADD COLUMN image_path TEXT;',
  ];
}
