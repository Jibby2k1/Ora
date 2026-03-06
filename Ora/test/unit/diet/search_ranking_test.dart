import 'package:flutter_test/flutter_test.dart';
import 'package:ora/data/food/search_ranker.dart';
import 'package:ora/domain/models/food_models.dart';

void main() {
  test('exact match outranks partial match', () {
    final ranker = FoodSearchRanker();
    final ranked = ranker.rankResults(
      input: const [
        FoodSearchResult(
          id: 'protein_shake',
          source: FoodSource.usdaFdc,
          name: 'protein shake',
          dataType: 'foundation',
        ),
        FoodSearchResult(
          id: 'protein_bar',
          source: FoodSource.usdaFdc,
          name: 'protein bar',
          dataType: 'foundation',
        ),
        FoodSearchResult(
          id: 'chicken_bar',
          source: FoodSource.usdaFdc,
          name: 'chicken bar',
          dataType: 'foundation',
        ),
      ],
      query: 'protein shake',
      category: FoodSearchCategory.commonFoods,
      recentNames: const <String>{},
    );

    expect(ranked.first.id, 'protein_shake');
  });

  test('token coverage influences ranking order', () {
    final ranker = FoodSearchRanker();
    final ranked = ranker.rankResults(
      input: const [
        FoodSearchResult(
          id: 'chicken_broth',
          source: FoodSource.usdaFdc,
          name: 'chicken broth',
          dataType: 'foundation',
        ),
        FoodSearchResult(
          id: 'chicken_thigh',
          source: FoodSource.usdaFdc,
          name: 'chicken thigh',
          dataType: 'foundation',
        ),
        FoodSearchResult(
          id: 'thigh_wrap',
          source: FoodSource.usdaFdc,
          name: 'thigh wrap',
          dataType: 'foundation',
        ),
      ],
      query: 'chicken thigh',
      category: FoodSearchCategory.commonFoods,
      recentNames: const <String>{},
    );

    expect(ranked.first.id, 'chicken_thigh');
  });
}
