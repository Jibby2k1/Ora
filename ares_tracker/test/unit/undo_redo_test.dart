import 'package:flutter_test/flutter_test.dart';

import 'package:ares_tracker/core/command_bus/command.dart';
import 'package:ares_tracker/core/command_bus/undo_redo.dart';

void main() {
  test('undo redo stack flows', () {
    final stack = UndoRedoStack();

    stack.push(const SwitchExercise(1));
    stack.push(const SwitchExercise(2));

    expect(stack.undoCount, 2);
    expect(stack.redoCount, 0);

    final undo1 = stack.popUndo();
    expect(undo1, isNotNull);
    expect(stack.undoCount, 1);
    expect(stack.redoCount, 1);

    final redo1 = stack.popRedo();
    expect(redo1, isNotNull);
    expect(stack.undoCount, 2);
    expect(stack.redoCount, 0);
  });
}
