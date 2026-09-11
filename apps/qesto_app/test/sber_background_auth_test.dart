import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_browser/config/bank_connector_registry.dart';
import 'package:qesto/features/bank_browser/data/browser_profile_manager.dart';
import 'package:qesto/features/bank_browser/domain/bank_browser_models.dart';
import 'package:qesto/features/bank_browser/runtime/browser_controller.dart';
import 'package:qesto/features/bank_browser/sber/sber_auth_manager.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_page_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Browser browser;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('qesto-auth-fixture-');
    final profiles = BrowserProfileManager(rootDirectory: root);
    browser = _Browser(
      await profiles.createProfile(BankConnectorRegistry.sber),
      profiles,
    );
  });
  tearDown(() async {
    browser.dispose();
    await root.delete(recursive: true);
  });
  test(
    'background quick login uses only its own saved PIN and attempts once',
    () async {
      await SberPinVault(profileId: browser.profile.id).write('1234');
      final result = await const SberAuthManager().ensureAuthenticated(
        browser,
        _Detector([_pinPage, _dashboard]),
      );
      expect(result.state, SberConnectorState.authenticated);
      expect(result.pinAttempted, isTrue);
      expect(browser.authCalls, 1);
    },
  );
  test('missing own PIN does not borrow another profile PIN', () async {
    await const SberPinVault(profileId: 'other-fixture').write('1234');
    final result = await const SberAuthManager().ensureAuthenticated(
      browser,
      _Detector([_pinPage]),
    );
    expect(result.state, SberConnectorState.pinRequired);
    expect(browser.authCalls, 0);
  });
  test(
    'rejected keypad attempt requests user login without a second attempt',
    () async {
      await SberPinVault(profileId: browser.profile.id).write('1234');
      browser.accept = false;
      final result = await const SberAuthManager().ensureAuthenticated(
        browser,
        _Detector([_pinPage]),
      );
      expect(result.state, SberConnectorState.fullLoginRequired);
      expect(browser.authCalls, 1);
    },
  );
  test('full login is never filled automatically', () async {
    await SberPinVault(profileId: browser.profile.id).write('1234');
    final result = await const SberAuthManager().ensureAuthenticated(
      browser,
      _Detector([
        SberPageSnapshot(
          url: Uri.parse('https://online.sberbank.ru/login'),
          title: 'Войти',
          text: 'Логин пароль',
          pinMarkers: [],
          loginMarkers: ['login'],
        ),
      ]),
    );
    expect(result.state, SberConnectorState.fullLoginRequired);
    expect(browser.authCalls, 0);
  });

  test(
    'slow initial DOM and temporary login heading settle before quick PIN',
    () async {
      await SberPinVault(profileId: browser.profile.id).write('1234');
      var waits = 0;
      final result =
          await SberAuthManager(
            pause: (_) async {
              waits++;
            },
          ).ensureAuthenticated(
            browser,
            _Detector([
              SberPageSnapshot(
                url: Uri.parse('https://online.sberbank.ru/'),
                title: 'Сбер',
                text: '',
                pinMarkers: [],
                loginMarkers: [],
              ),
              SberPageSnapshot(
                url: Uri.parse('https://online.sberbank.ru/login'),
                title: 'Войти',
                text: 'Войти',
                pinMarkers: [],
                loginMarkers: ['login'],
              ),
              _pinPage,
              _dashboard,
            ]),
          );
      expect(result.state, SberConnectorState.authenticated);
      expect(browser.authCalls, 1);
      expect(waits, 2);
    },
  );

  test(
    'unready DOM is retryable loading error, not a forced full login',
    () async {
      final result = await SberAuthManager(pause: (_) async {})
          .ensureAuthenticated(
            browser,
            _Detector([
              SberPageSnapshot(
                url: Uri.parse('https://online.sberbank.ru/'),
                title: 'Сбер',
                text: '',
                pinMarkers: [],
                loginMarkers: [],
              ),
            ]),
          );
      expect(result.state, SberConnectorState.error);
      expect(result.failureCode, 'BANK_PAGE_NOT_READY');
      expect(browser.authCalls, 0);
    },
  );
}

final _pinPage = SberPageSnapshot(
  url: Uri.parse('https://online.sberbank.ru/login'),
  title: 'Введите код',
  text: '',
  pinMarkers: ['pin-heading', 'keypad', 'pin-input'],
  loginMarkers: [],
);
final _dashboard = SberPageSnapshot(
  url: Uri.parse('https://online.sberbank.ru/app/main'),
  title: 'Счета',
  text: 'Баланс',
  pinMarkers: [],
  loginMarkers: [],
);

class _Detector extends SberPageDetector {
  _Detector(this.pages);
  final List<SberPageSnapshot> pages;
  var index = 0;
  @override
  Future<SberPageSnapshot?> inspect(BrowserController browser) async {
    final page = pages[index.clamp(0, pages.length - 1)];
    index++;
    return page;
  }
}

class _Browser extends BrowserController {
  _Browser(BankProfile profile, BrowserProfileManager profiles)
    : super(
        profile: profile,
        bank: BankConnectorRegistry.sber,
        profileManager: profiles,
        onNotice: (_) {},
      );
  var authCalls = 0;
  var accept = true;
  @override
  Future<dynamic> evaluateConnectorJavascript(
    String script, {
    BrowserMode mode = BrowserMode.read,
  }) async {
    expect(mode, BrowserMode.auth);
    expect(script, contains('QESTO_SBER_AUTH_V1'));
    authCalls++;
    return accept ? '{"ok":true}' : '{"ok":false}';
  }
}
