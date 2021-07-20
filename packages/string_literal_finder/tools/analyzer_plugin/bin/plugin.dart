import 'dart:isolate';

import 'package:string_literal_finder/analyser_plugin.dart';

void main(List<String> args, SendPort sendPort) {
  start(args, sendPort);
}
