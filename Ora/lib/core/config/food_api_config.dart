class FoodApiConfig {
  const FoodApiConfig._();

  static const String usdaFdcApiKey = String.fromEnvironment(
    'USDA_FDC_API_KEY',
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

  static bool get hasUsdaKey => usdaFdcApiKey.trim().isNotEmpty;

  static bool get hasNutritionixCredentials =>
      nutritionixAppId.trim().isNotEmpty &&
      nutritionixApiKey.trim().isNotEmpty;
}
