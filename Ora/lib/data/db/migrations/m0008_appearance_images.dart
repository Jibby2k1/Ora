List<String> migration0008() {
  return [
    'ALTER TABLE appearance_entry ADD COLUMN image_path TEXT;',
  ];
}
