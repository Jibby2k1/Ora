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

  test('generic chicken breast matches outrank branded/partial matches', () {
    final ranker = FoodSearchRanker();
    final ranked = ranker.rankResults(
      input: const [
        FoodSearchResult(
          id: 'brand_strips',
          source: FoodSource.openFoodFacts,
          name: 'Tyson grilled chicken breast strips',
          brand: 'Tyson',
          isBranded: true,
        ),
        FoodSearchResult(
          id: 'generic_raw',
          source: FoodSource.usdaFdc,
          name: 'Chicken breast meat only raw',
          dataType: 'Foundation',
        ),
        FoodSearchResult(
          id: 'generic_cooked',
          source: FoodSource.usdaFdc,
          name: 'Chicken breast roasted',
          dataType: 'SR Legacy',
        ),
        FoodSearchResult(
          id: 'partial',
          source: FoodSource.usdaFdc,
          name: 'Chicken salad',
          dataType: 'Foundation',
        ),
      ],
      query: 'chicken breast',
      category: FoodSearchCategory.all,
      recentNames: const <String>{},
    );

    expect(ranked.take(2).map((result) => result.id),
        containsAll(['generic_raw', 'generic_cooked']));
    expect(ranked.first.id, isNot('brand_strips'));
    expect(ranked.first.id, isNot('partial'));
  });

  test('branded queries can elevate explicit brand matches', () {
    final ranker = FoodSearchRanker();
    final ranked = ranker.rankResults(
      input: const [
        FoodSearchResult(
          id: 'generic',
          source: FoodSource.usdaFdc,
          name: 'Ultra filtered milk',
          dataType: 'Foundation',
        ),
        FoodSearchResult(
          id: 'brand',
          source: FoodSource.openFoodFacts,
          name: 'Fairlife ultra filtered milk',
          brand: 'Fairlife',
          isBranded: true,
        ),
      ],
      query: 'fairlife milk',
      category: FoodSearchCategory.all,
      recentNames: const <String>{},
    );

    expect(ranked.first.id, 'brand');
  });

  test('ranking does not throw for short non-matching candidate names', () {
    final ranker = FoodSearchRanker();
    expect(
      () => ranker.rankResults(
        input: const [
          FoodSearchResult(
            id: 'short',
            source: FoodSource.openFoodFacts,
            name: 'ham',
            isBranded: true,
          ),
          FoodSearchResult(
            id: 'generic_raw',
            source: FoodSource.usdaFdc,
            name: 'Chicken breast meat only raw',
            dataType: 'Foundation',
          ),
        ],
        query: 'chicken breast',
        category: FoodSearchCategory.all,
        recentNames: const <String>{},
      ),
      returnsNormally,
    );
  });
}
