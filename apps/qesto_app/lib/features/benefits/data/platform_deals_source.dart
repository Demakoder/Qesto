import 'package:http/http.dart' as http;

import 'platform_deals_source_stub.dart'
    if (dart.library.io) 'platform_deals_source_io.dart'
    as implementation;

Future<String?> fetchPlatformDealsJson({http.Client? client}) =>
    implementation.fetchPlatformDealsJson(client: client);
