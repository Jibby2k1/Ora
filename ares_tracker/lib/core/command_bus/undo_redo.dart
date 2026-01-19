import 'command.dart';

class UndoRedoStack {
  final List<Command> _undo = [];
  final List<Command> _redo = [];

  void push(Command inverse) {
    _undo.add(inverse);
    _redo.clear();
  }

  Command? popUndo() {
    if (_undo.isEmpty) return null;
    final cmd = _undo.removeLast();
    _redo.add(cmd);
    return cmd;
  }

  Command? popRedo() {
    if (_redo.isEmpty) return null;
    final cmd = _redo.removeLast();
    _undo.add(cmd);
    return cmd;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  int get undoCount => _undo.length;
  int get redoCount => _redo.length;
}
