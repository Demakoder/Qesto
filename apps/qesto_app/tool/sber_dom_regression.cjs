// Offline synthetic browser test. Requires Playwright (via NODE_PATH or local
// install); QESTO_CHROMIUM_EXECUTABLE optionally selects an installed Chromium.
// Never uses a persistent browser profile or any real bank data.
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const { chromium } = require('playwright');
const source = fs.readFileSync(path.join(__dirname, '../lib/features/bank_browser/sber/sber_extractors.dart'), 'utf8');
const script = source.split("const _transactionsScript = r'''")[1]?.split("''';")[0];
const accountScript = source.split("const _accountsScript = r'''")[1]?.split("''';")[0];
const hasMoreScript = source.split("const _hasMoreTransactionsScript = r'''")[1]?.split("''';")[0];
const navigationSource = fs.readFileSync(path.join(__dirname, '../lib/features/bank_browser/sber/sber_navigator.dart'), 'utf8');
const historyLinkScript = navigationSource.split("const _historyLinkScript = r'''")[1]?.split("''';")[0];
const readinessSource = fs.readFileSync(path.join(__dirname, '../lib/features/bank_browser/sber/sber_readiness.dart'), 'utf8');
const readinessScript = readinessSource.split("const _readinessScript = r'''")[1]?.split("''';")[0];
assert.ok(script, 'Production connector script must be present');
const cases = [
  ['complete', '<p>Магазин</p><span>100,25 ₽</span><p>Оплата товаров и услуг</p><div><span>Платёжный счёт:</span><span>9 000 ₽</span></div>'],
  ['loading', '<p>Магазин</p><p>Оплата товаров и услуг</p><div><span>Платёжный счёт:</span><span>9 000 ₽</span></div>'],
  ['loading-reward', '<p>Магазин</p><span>+6 баллов</span><p>Оплата товаров и услуг</p><p>Остаток: 9 000 ₽</p>'],
  ['bonus', '<p>Магазин</p><span>+6 баллов</span><p>Начисление бонусов</p><p>Остаток: 9 000 ₽</p>'],
  ['service', '<p>Выписка по счёту</p><p>Остаток: 9 000 ₽</p>'],
  ['own', '<p>Платёжный счёт</p><span>150,22 ₽</span><p>Между своими</p>'],
  ['fee-loading', '<p>Магазин</p><p>Оплата товаров и услуг</p><div><span>Комиссия</span><span>30,49 ₽</span></div>'],
  ['empty', ''],
];
(async () => {
  const browser = await chromium.launch({
    ...(process.env.QESTO_CHROMIUM_EXECUTABLE ? {executablePath: process.env.QESTO_CHROMIUM_EXECUTABLE} : {}),
    headless: true,
  });
  const watchdog = setTimeout(() => { console.error('Offline DOM test timed out'); process.exitCode = 1; browser.close(); }, 45000);
  try {
    const context = await browser.newContext({javaScriptEnabled: false});
    await context.route('**/*', route => route.abort());
    const page = await context.newPage();
    await page.setContent('<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'"><section><ul aria-label="Операции 10 августа 2026">' +
      cases.map(([id, body]) => `<li style="min-height:30px"><a style="display:block;min-height:30px" href="https://online.sberbank.ru/app/operations/details/${id}">${body}</a></li>`).join('') + '</ul></section>');
    const rows = JSON.parse(await page.evaluate(script));
    const get = id => rows.find(r => r.id === id);
    assert.equal(rows.length, cases.length);
    assert.equal(get('complete').amountValue, 100.25);
    for (const id of ['loading', 'loading-reward', 'fee-loading']) {
      assert.equal(get(id).amount, '', id);
      assert.equal(get(id).nonCashKind, '', id);
    }
    assert.equal(get('bonus').nonCashKind, 'reward');
    assert.equal(get('service').nonCashKind, 'service');
    assert.equal(get('own').operationType, 'Между своими');
    assert.equal(get('own').amountValue, 150.22);
    assert.equal(get('empty').text, '');
    await page.setContent(`<main><div>В кошельке 9 876,54 ₽
      <div><a href="https://online.sberbank.ru/app/cta/details/zero" aria-label="Платёжный счёт 1010. Баланс 0. руб.. Привязана 1 карта.">0 ₽ Счёт •• 1010</a><button aria-label="Карта 1111">1111</button></div>
      <div><a href="https://online.sberbank.ru/app/cta/details/positive" aria-label="Платёжный счёт 2020. Баланс 9 876,54. руб.. Привязана 1 карта.">9 876,54 ₽ Счёт •• 2020</a><button aria-label="Карта 2222">2222</button></div>
      <div><a href="https://online.sberbank.ru/app/cta/details/zero2" aria-label="Платёжный счёт 3030. Баланс 0. руб.. Привязана 1 карта.">0 ₽ Счёт •• 3030</a><button aria-label="Карта 3333">3333</button></div>
      </div></main><button disabled>Показать ещё</button>`);
    const accounts = JSON.parse(await page.evaluate(accountScript));
    assert.equal(accounts.length, 3);
    assert.deepEqual(accounts.map(a => a.balance), ['0 ₽', '9 876,54 ₽', '0 ₽']);
    assert.deepEqual(accounts.map(a => a.cards), [['1111'], ['2222'], ['3333']]);
    assert.ok(accounts.every(a => !a.text.includes('В кошельке')));
    assert.equal(await page.evaluate(hasMoreScript), '1', 'Disabled pagination is not proof of complete history');
    const scopedHtml = '<button data-filter="product">МИР Сберкарта •• 1234</button>' +
      '<ul aria-label="Операции 8 сентября 2026"><li><a href="/app/operations/details?uohId=test">' +
      '<p>Shop</p><span>100,25 ₽</span><p>Оплата товаров и услуг</p></a></li></ul>';
    await context.route('https://qesto.invalid/**', route => route.fulfill({contentType:'text/html', body:scopedHtml}));
    await page.goto('https://qesto.invalid/app/operations?usedResource=card:12345678');
    const scoped = JSON.parse(await page.evaluate(script));
    assert.equal(scoped.length, 1);
    assert.equal(scoped[0].account, '12345678');
    await page.goto('https://qesto.invalid/app/operations');
    assert.equal(JSON.parse(await page.evaluate(script))[0].account, '');
    await page.setContent('<a href="https://online.sberbank.ru/app/cards/details/12345678">МИР Сберкарта<br>•• 1234<br>Доступно 5 000,25 ₽</a>');
    const cards = JSON.parse(await page.evaluate(accountScript));
    assert.equal(cards.length, 1);
    assert.deepEqual(cards[0].historyResources, ['card:12345678']);
    assert.equal(cards[0].balance, '5 000,25 ₽');
    await page.setContent('<section><h2>История</h2><a id="history" href="/app/operations">Ещё</a></section>' +
      '<section><h2>Расходы</h2><a id="spend" href="/app/pfm/alf">Ещё</a></section>');
    await page.evaluate(() => { window.clicked = []; document.querySelectorAll('a').forEach(n => {n.click = () => window.clicked.push(n.id);}); });
    assert.equal(await page.evaluate(historyLinkScript), '1');
    assert.deepEqual(await page.evaluate(() => window.clicked), ['history']);
    await page.setContent('<button data-filter="product">Карта или счёт</button>');
    assert.equal(await page.evaluate(readinessScript), 'loading', 'History shell is not empty history');
    await page.setContent('<p>Нет операций</p>');
    assert.equal(await page.evaluate(readinessScript), 'ready');
    await page.setContent('<p>Нет операций</p><div role="progressbar">Загрузка</div>');
    assert.equal(await page.evaluate(readinessScript), 'loading');
    await page.setContent('<h1>Подтвердите, что вы не робот</h1>');
    assert.equal(await page.evaluate(readinessScript), 'blocked');
    console.log(JSON.stringify({syntheticCasesPassed: cases.length + 12}));
  } finally { clearTimeout(watchdog); await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
