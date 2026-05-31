import 'dart:io';

bool localFileExists(String path) => File(path).existsSync();
