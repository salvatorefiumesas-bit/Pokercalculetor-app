import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Aggiornamento automatico tramite le Release di GitHub.
///
/// Ogni build di `main` pubblica una release `v1.0.N` con l'APK allegato,
/// dove N è il numero di build (= versionCode dell'app).
class Updater {
  Updater._();

  static const _channel = MethodChannel('app/update');
  static const _latestUrl =
      'https://api.github.com/repos/salvatorefiumesas-bit/Pokercalculetor-app/releases/latest';
  static bool _checked = false;

  /// Controlla una sola volta per avvio; in caso di errore non mostra nulla.
  static Future<void> checkForUpdate(BuildContext context) async {
    if (_checked || !Platform.isAndroid) return;
    _checked = true;
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('info');
      if (info == null) return;
      final currentCode = (info['versionCode'] as num).toInt();
      final release = await _fetchJson(_latestUrl);
      final tag = release['tag_name'] as String? ?? '';
      final latestCode = int.tryParse(RegExp(r'(\d+)$').firstMatch(tag)?.group(1) ?? '') ?? 0;
      if (latestCode <= currentCode) return;
      final assets = (release['assets'] as List?) ?? const [];
      final apk = assets.cast<Map<String, dynamic>>().where((a) => (a['name'] as String).endsWith('.apk')).firstOrNull;
      if (apk == null) return;
      if (!context.mounted) return;
      final notes = (release['body'] as String? ?? '').split('\n').first.trim();
      final yes = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.system_update, size: 36),
          title: const Text('Nuova versione disponibile'),
          content: Text(
            'È disponibile la versione ${tag.replaceFirst('v', '')} '
            '(hai la ${info['versionName']}).\n\n'
            '${notes.isEmpty ? '' : '$notes\n\n'}Vuoi aggiornare?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sì')),
          ],
        ),
      );
      if (yes != true || !context.mounted) return;
      await _downloadAndInstall(context, apk['browser_download_url'] as String, info['downloadDir'] as String);
    } catch (_) {
      // Niente rete o API non raggiungibile: si riprova al prossimo avvio.
    }
  }

  static Future<Map<String, dynamic>> _fetchJson(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  static Future<void> _downloadAndInstall(BuildContext context, String url, String dir) async {
    // Android chiede il permesso di installare app da questa sorgente.
    final canInstall = await _channel.invokeMethod<bool>('canInstall') ?? false;
    if (!canInstall) {
      if (!context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permesso necessario'),
          content: const Text(
            'Per installare l\'aggiornamento, consenti a Poker GTO di installare app. '
            'Si aprirà l\'impostazione: attiva l\'opzione, torna qui e premi di nuovo "Sì" '
            'al prossimo avvio.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apri impostazioni')),
          ],
        ),
      );
      if (go == true) await _channel.invokeMethod('openInstallSettings');
      _checked = false; // al ritorno nell'app si può riprovare
      return;
    }

    final progress = ValueNotifier<double?>(null);
    final error = ValueNotifier<String?>(null);
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Download aggiornamento'),
        content: ValueListenableBuilder<String?>(
          valueListenable: error,
          builder: (ctx, err, _) => err != null
              ? Text('Download non riuscito: $err')
              : ValueListenableBuilder<double?>(
                  valueListenable: progress,
                  builder: (ctx, p, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                    LinearProgressIndicator(value: p),
                    const SizedBox(height: 8),
                    Text(p == null ? 'Connessione…' : '${(p * 100).toStringAsFixed(0)}%'),
                  ]),
                ),
        ),
        actions: [
          ValueListenableBuilder<String?>(
            valueListenable: error,
            builder: (ctx, err, _) => err == null
                ? const SizedBox.shrink()
                : TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
          ),
        ],
      ),
    );

    final client = HttpClient();
    try {
      final file = File('$dir/update.apk');
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total;
      }
      await sink.close();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await _channel.invokeMethod('install', {'path': file.path});
    } catch (e) {
      error.value = e.toString();
    } finally {
      client.close();
    }
  }
}
