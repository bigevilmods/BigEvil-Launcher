import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

const githubTokenVariable = 'BIGEVIL_GITHUB_TOKEN';

String? _validToken(String value) {
  final token = value.trim();
  return RegExp(r'^[A-Za-z0-9_]{1,512}$').hasMatch(token) ? token : null;
}

String? parseGitHubToken(String dotenv) {
  final assignment = RegExp(
    r'^\s*(?:export\s+)?BIGEVIL_GITHUB_TOKEN\s*=\s*'
    r"""(?:"([A-Za-z0-9_]+)"|'([A-Za-z0-9_]+)'|([A-Za-z0-9_]+))"""
    r'\s*(?:#.*)?$',
  );
  for (final line in const LineSplitter().convert(dotenv)) {
    final match = assignment.firstMatch(line);
    if (match != null) return _validToken((match[1] ?? match[2] ?? match[3])!);
  }
  return null;
}

Future<String?> loadGitHubToken() async {
  final environment = _validToken(
    Platform.environment[githubTokenVariable] ?? '',
  );
  if (environment != null) return environment;

  Future<String?> read(File file) async {
    try {
      if (await file.length() > 16 * 1024) return null;
      return parseGitHubToken(await file.readAsString());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  if (Platform.isWindows || Platform.isLinux) {
    final executable = File(Platform.resolvedExecutable);
    final token = await read(File('${executable.parent.path}/.env'));
    if (token != null) return token;
  }
  try {
    final support = await getApplicationSupportDirectory();
    return read(File('${support.path}/.env'));
  } catch (_) {
    return null;
  }
}
