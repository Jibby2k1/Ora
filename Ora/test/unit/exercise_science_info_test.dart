import 'package:flutter_test/flutter_test.dart';

import 'package:ora/domain/models/exercise_science_info.dart';

void main() {
  test('orders sections and resolves legacy citations as source documents', () {
    final info = ExerciseScienceInfo(
      exerciseId: 1,
      instructions: const [],
      avoid: const [],
      citations: const ['Author (2024). Paper. Journal.'],
      visualAssetPaths: const [],
      sections: ExerciseScienceSection.listFromDynamic([
        {
          'id': 'effectiveness',
          'title': 'Effectiveness',
          'items': [
            {
              'title': 'Useful claim',
              'source_ids': ['s1']
            },
          ],
        },
        {
          'title': 'Custom Notes',
          'summary': 'Watch the setup closely.',
        },
        {
          'id': 'safety',
          'title': 'Safety',
          'items': [
            {
              'title': 'Brace first',
              'source_ids': ['S1']
            },
          ],
        },
      ]),
    );

    expect(
      info.orderedSections.map((section) => section.normalizedId).toList(),
      ['safety', 'effectiveness', 'custom_notes'],
    );

    final source = info.sourceById('s1');
    expect(source, isNotNull);
    expect(source!.normalizedId, 'S1');
    expect(source.citation, contains('Author (2024)'));
  });

  test('normalizes loose section and source document shapes', () {
    final sections = ExerciseScienceSection.listFromDynamic([
      {
        'key': 'effectiveness',
        'summary': 'Conservative summary.',
        'claims': [
          {
            'claim': 'Primary claim',
            'explanation': 'Short detail.',
            'sources': ['doc 1'],
          },
          'Fallback bullet',
        ],
      },
    ]);

    expect(sections, hasLength(1));
    expect(sections.single.title, 'Effectiveness');
    expect(sections.single.items, hasLength(2));
    expect(sections.single.items.first.sourceIds, ['DOC1']);

    final documents = ExerciseScienceSourceDocument.listFromDynamic([
      {
        'document_id': 'doc 1',
        'title': 'Paper Title',
        'reference': 'Author (2022). Paper Title. Journal.',
        'year': '2022',
        'type': 'Review',
        'note': 'Useful for critique.',
      },
      'Second citation',
    ]);

    expect(documents, hasLength(2));
    expect(documents.first.normalizedId, 'DOC1');
    expect(documents.first.year, 2022);
    expect(documents.first.documentType, 'Review');
    expect(documents[1].normalizedId, 'S2');
  });
}
