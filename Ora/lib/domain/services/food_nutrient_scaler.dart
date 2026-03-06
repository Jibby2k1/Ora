import '../models/food_models.dart';

class FoodScaledView {
  const FoodScaledView({
    required this.food,
    required this.serving,
    required this.quantity,
    required this.totalGrams,
    required this.isApproximateConversion,
    required this.scaleFactor,
    required this.nutrients,
  });

  final FoodItem food;
  final ServingOption serving;
  final double quantity;
  final double? totalGrams;
  final bool isApproximateConversion;
  final double scaleFactor;
  final Map<NutrientKey, NutrientValue> nutrients;

  double get calories => nutrients[NutrientKey.calories]?.amount ?? 0;
  double get protein => nutrients[NutrientKey.protein]?.amount ?? 0;
  double get carbs => nutrients[NutrientKey.carbs]?.amount ?? 0;
  double get fat => nutrients[NutrientKey.fatTotal]?.amount ?? 0;
  double get fiber => nutrients[NutrientKey.fiber]?.amount ?? 0;
  double get sugar => nutrients[NutrientKey.sugar]?.amount ?? 0;
  double get sodium => nutrients[NutrientKey.sodium]?.amount ?? 0;
}

class FoodNutrientScaler {
  const FoodNutrientScaler();

  FoodScaledView scale({
    required FoodItem food,
    required ServingOption serving,
    required double quantity,
  }) {
    final safeQuantity = quantity <= 0 ? 1.0 : quantity;
    final resolved = _resolveScaleFactor(
      food: food,
      serving: serving,
      quantity: safeQuantity,
    );

    final scaledNutrients = <NutrientKey, NutrientValue>{};
    food.nutrients.forEach((key, value) {
      scaledNutrients[key] = value.copyWith(amount: value.amount * resolved.factor);
    });

    return FoodScaledView(
      food: food,
      serving: serving,
      quantity: safeQuantity,
      totalGrams: resolved.totalGrams,
      isApproximateConversion: resolved.isApproximate,
      scaleFactor: resolved.factor,
      nutrients: scaledNutrients,
    );
  }

  _ScaleResult _resolveScaleFactor({
    required FoodItem food,
    required ServingOption serving,
    required double quantity,
  }) {
    if (food.nutrientsPer100g) {
      final totalGrams = _resolveServingGrams(serving, quantity: quantity) ??
          _resolveServingGrams(food.defaultServing, quantity: quantity);
      if (totalGrams != null && totalGrams > 0) {
        return _ScaleResult(
          factor: totalGrams / 100,
          totalGrams: totalGrams,
          isApproximate: false,
        );
      }
      return _ScaleResult(
        factor: quantity,
        totalGrams: null,
        isApproximate: true,
      );
    }

    final defaultServing = food.defaultServing;
    final selectedGrams = _resolveServingGrams(serving, quantity: quantity);
    final baseGrams = _resolveServingGrams(defaultServing, quantity: 1);
    if (selectedGrams != null && baseGrams != null && baseGrams > 0) {
      return _ScaleResult(
        factor: selectedGrams / baseGrams,
        totalGrams: selectedGrams,
        isApproximate: false,
      );
    }

    if (serving.id == defaultServing.id) {
      return _ScaleResult(
        factor: quantity,
        totalGrams: selectedGrams,
        isApproximate: false,
      );
    }

    if (serving.unit != null &&
        serving.unit == defaultServing.unit &&
        defaultServing.amount > 0) {
      return _ScaleResult(
        factor: (serving.amount * quantity) / defaultServing.amount,
        totalGrams: selectedGrams,
        isApproximate: false,
      );
    }

    return _ScaleResult(
      factor: quantity,
      totalGrams: selectedGrams,
      isApproximate: true,
    );
  }

  double? _resolveServingGrams(ServingOption serving, {required double quantity}) {
    if (serving.gramWeight != null && serving.gramWeight! > 0) {
      return serving.gramWeight! * quantity;
    }
    final unit = serving.unit?.toLowerCase();
    if (unit == 'g' || unit == 'gram' || unit == 'grams') {
      return serving.amount * quantity;
    }
    return null;
  }
}

class _ScaleResult {
  const _ScaleResult({
    required this.factor,
    required this.totalGrams,
    required this.isApproximate,
  });

  final double factor;
  final double? totalGrams;
  final bool isApproximate;
}
