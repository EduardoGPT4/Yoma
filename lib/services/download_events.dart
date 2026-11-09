import 'dart:async';

class DownloadEvents {
  static final _controller = StreamController<String>.broadcast();
  static Stream<String> get completedFolders => _controller.stream;
  static void completed(String folder) => _controller.add(folder);
}
