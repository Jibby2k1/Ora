import 'command.dart';

class UndoRedoStack {
  final List<Command> _undo = [];
  final List<Command> _redo = [];

  void pushUndo(Command inverse) {
    _undo.add(inverse);
    _redo.clear();
  }

  Command? popUndo() {
    if (_undo.isEmpty) return null;
    return _undo.removeLast();
  }

  Command? popRedo() {
    if (_redo.isEmpty) return null;
    return _redo.removeLast();
  }

  void pushRedo(Command inverse) {
    _redo.add(inverse);
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  int get undoCount => _undo.length;
  int get redoCount => _redo.length;
}
