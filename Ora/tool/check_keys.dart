import 'package:ora/core/config/food_api_config.dart';
import 'package:ora/data/food/food_repository.dart';
import 'package:ora/data/db/db.dart';
import 'package:ora/data/repositories/diet_repo.dart';

Future<void> main() async {
  print('hasUsda=${FoodApiConfig.hasUsdaKey}');
  print('usda key len=${FoodApiConfig.usdaFdcApiKey.length}');
  final repo = FoodRepository(db: AppDatabase.instance, dietRepo: DietRepo(AppDatabase.instance));
  print('isUsdaEnabled=${repo.isUsdaEnabled}, isNutritionixEnabled=${repo.isNutritionixEnabled}');
}
