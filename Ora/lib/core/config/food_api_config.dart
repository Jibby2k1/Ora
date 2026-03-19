class FoodApiConfig {
  const FoodApiConfig._();

  // Bundled app key used when no --dart-define USDA key is provided.
  // Note: client-side keys can be extracted from app binaries.
  static const String _bundledUsdaFdcApiKey =
      'K2ahcaJSA08M2Xs9wOpLh8yaSvSoowqNKtFql6OY';

  static const String _usdaFdcApiKey = String.fromEnvironment(
    'USDA_FDC_API_KEY',
    defaultValue: '',
  );

  static const String _legacyUsdaApiKey = String.fromEnvironment(
    'USDA_API_KEY',
    defaultValue: '',
  );

  static const String nutritionixAppId = String.fromEnvironment(
    'NUTRITIONIX_APP_ID',
    defaultValue: '',
  );

  static const String nutritionixApiKey = String.fromEnvironment(
    'NUTRITIONIX_API_KEY',
    defaultValue: '',
  );

  static String get usdaFdcApiKey {
    if (_usdaFdcApiKey.trim().isNotEmpty) {
      return _usdaFdcApiKey.trim();
    }
    if (_legacyUsdaApiKey.trim().isNotEmpty) {
      return _legacyUsdaApiKey.trim();
    }
    return _bundledUsdaFdcApiKey;
  }

  static bool get hasUsdaKey => usdaFdcApiKey.isNotEmpty;

  static bool get isUsingDemoUsdaKey => usdaFdcApiKey == 'DEMO_KEY';

  static bool get hasNutritionixCredentials =>
      nutritionixAppId.trim().isNotEmpty &&
      nutritionixApiKey.trim().isNotEmpty;
}
