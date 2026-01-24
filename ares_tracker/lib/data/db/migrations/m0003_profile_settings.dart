import '../schema.dart';

List<String> migration0003() {
  return [
    createTableUserProfile,
    createTableAppSettings,
  ];
}
