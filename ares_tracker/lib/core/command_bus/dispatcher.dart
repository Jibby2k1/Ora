import 'command.dart';
import 'reducers.dart';

class CommandDispatcher {
  CommandDispatcher(this._reducer);

  final CommandReducer _reducer;

  CommandResult dispatch(Command command) {
    return _reducer(command);
  }
}
