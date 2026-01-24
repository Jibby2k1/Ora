import 'command.dart';

typedef CommandReducer = Future<CommandResult> Function(Command command);
