import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'entry.dart';
import 'localization.dart';
export 'entry.dart';

class Library {
  static const android = MethodChannel('bigevil/android');
  static final catalogUri = Uri.https(
    'raw.githubusercontent.com',
    '/bigevilmods/BigEvil-Launcher/refs/heads/main/catalog.json',
  );

  static Future<List<Entry>> load() async {
    const timeout = Duration(seconds: 15);
    const maximumBytes = 2 * 1024 * 1024;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(catalogUri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: catalogUri);
      }
      final body = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        if (body.length + chunk.length > maximumBytes) {
          throw const FormatException('Catalog exceeds 2 MiB');
        }
        body.add(chunk);
      }
      return parseCatalog(utf8.decode(body.takeBytes()));
    } finally {
      client.close(force: true);
    }
  }

  static List<Entry> parseCatalog(String source) {
    final data = jsonDecode(source);
    if (data is! List) {
      throw const FormatException('Expected a list of catalog entries');
    }
    return [
      for (final item in data)
        if (item is Map<String, dynamic>)
          _catalogEntry(Entry.fromJson(item))
        else
          throw const FormatException('Expected a catalog entry object'),
    ];
  }

  static Entry _catalogEntry(Entry entry) {
    for (final address in [
      entry.target,
      entry.coverPath,
      entry.backgroundPath,
      entry.repositoryUrl,
      entry.downloadUrl,
      entry.onlineUrl,
    ]) {
      if (address != null && address.isNotEmpty && !isWebLink(address)) {
        throw const FormatException('Catalog links must use HTTP or HTTPS');
      }
    }
    return entry;
  }

  static bool isWebLink(String value) => webUri(value) != null;

  static Uri? webUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty)
      return null;
    return uri;
  }

  static Future<void> openWebLink(String address) async {
    final uri = webUri(address);
    if (uri == null)
      throw LocalizedFailure((messages) => messages.invalidAddress);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw LocalizedFailure((messages) => messages.systemLinkError);
    }
  }

  static Future<void> open(Entry entry) => openWebLink(entry.target);
}
