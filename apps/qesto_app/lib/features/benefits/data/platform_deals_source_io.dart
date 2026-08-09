import 'dart:io';

import 'package:http/http.dart' as http;

import 'telegram_deals_ingestion.dart';

Future<String?> fetchPlatformDealsJson({http.Client? client}) async {
  if (!Platform.isAndroid) return null;
  return TelegramDealsIngestion(client: client).fetchOffersJson();
}
