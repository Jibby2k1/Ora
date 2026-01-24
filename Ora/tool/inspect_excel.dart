import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final bytes = File('Examples/Raul Split - HILV Program.xlsx').readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables.values.first;
  if (sheet == null) {
    print('no sheet');
    return;
  }
  for (var i = 0; i < 6; i++) {
    final row = sheet.rows[i];
    final values = row.map((cell) => cell?.value).toList();
    final types = row.map((cell) => cell?.value.runtimeType).toList();
    print('$i values: $values');
    print('$i types: $types');
  }
}
