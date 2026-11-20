/*
 * site-tech-detect.js — «міні-Wappalyzer»: показує, на чому зроблено сайт.
 *
 * ЩО ЦЕ
 *   Сніпет для консолі Chrome DevTools. Визначає фреймворки, CMS, конструктори,
 *   аналітику та сервер/хостинг сайту, який зараз відкритий у вкладці.
 *   Написаний як заміна розширенню Wappalyzer (те за замовчуванням відправляє
 *   домени, які ви аналізуєте, на свій сервер). Зародок майбутнього власного
 *   розширення для Chrome: технології + шрифти (як WhatFont) на одній панелі.
 *
 * ЯК ЗАПУСТИТИ
 *   1. Відкрити сайт → F12 → вкладка Console.
 *   2. Вставити весь вміст файлу → Enter.
 *   3. Результат — таблиця у консолі.
 *   Зручніше: DevTools → Sources → Snippets → New snippet → вставити →
 *   потім запуск через Ctrl+Enter або правою кнопкою → Run.
 *
 * ОБМЕЖЕННЯ
 *   - Це ~20 найпоширеніших ознак, а не тисячі, як у Wappalyzer.
 *   - Якщо сайт навмисно ховає технології (прибраний meta generator,
 *     перейменовані шляхи збірки), нічого не знайде — як і Wappalyzer.
 *   - DNS-записи (MX/TXT) з браузера не видно. Для них у PowerShell:
 *       Resolve-DnsName example.com -Type MX
 *   - Альтернатива без нічого: radar.cloudflare.com/scan (визначення Wappalyzer).
 *
 * НОТАТКИ ДЛЯ МАЙБУТНЬОГО РОЗШИРЕННЯ
 *   - Content script не бачить змінних сторінки (__NEXT_DATA__, jQuery…):
 *     потрібен world: 'MAIN' (chrome.scripting.executeScript або маніфест).
 *   - Заголовки відповіді брати з chrome.webRequest.onHeadersReceived,
 *     а не повторним fetch.
 *   - DNS — через DNS-over-HTTPS (https://cloudflare-dns.com/dns-query).
 *   - Шрифти: document.fonts + getComputedStyle(el).fontFamily.
 *   - Додати українські платформи: Tilda вже є; Хорошоп, Prom — ще ні.
 *
 * Створено: 2026-11-20 (разом з Claude, під час чистки розширень Chrome).
 */

(async () => {
  const w = window, d = document, q = s => d.querySelector(s), r = [];
  const add = (cond, name) => { if (cond) r.push(typeof cond === 'string' ? `${name} ${cond}` : name); };
  const all = [...d.querySelectorAll('body *')].slice(0, 3000);

  // Фреймворки
  add(all.some(e => Object.keys(e).some(k => k.startsWith('__react'))), 'React');
  add(w.__NEXT_DATA__ || q('#__next') || q('script[src*="/_next/"]'), 'Next.js');
  add(w.__NUXT__ || w.$nuxt, 'Nuxt');
  add(q('[data-v-app]') || all.some(e => e.__vue__ || e.__vue_app__), 'Vue');
  add(q('[ng-version]')?.getAttribute('ng-version'), 'Angular');
  add(all.some(e => [...e.classList].some(c => c.startsWith('svelte-'))), 'Svelte');
  // Astro: острови, meta generator, папка збірки /_astro/, атрибути scoped-стилів
  add(q('astro-island') || q('meta[name="generator"][content^="Astro"]') || q('link[href*="/_astro/"],script[src*="/_astro/"]') || all.some(e => [...e.attributes].some(a => a.name.startsWith('data-astro-cid'))), 'Astro');
  add(q('#___gatsby'), 'Gatsby');
  add(w.jQuery?.fn?.jquery, 'jQuery');

  // CMS і конструктори
  add(q('link[href*="/wp-content/"],script[src*="/wp-content/"]'), 'WordPress');
  add(w.Shopify, 'Shopify');
  add(q('#allrecords'), 'Tilda');
  add(q('html[data-wf-site]'), 'Webflow');
  add(w.wixBiSession, 'Wix');

  // Аналітика
  add(w.google_tag_manager, 'Google Tag Manager');
  add(w.gtag || w.ga, 'Google Analytics');
  add(w.fbq, 'Meta Pixel');

  add(q('meta[name="generator"]')?.content, 'Generator:');

  // Сервер / хостинг (заголовки відповіді)
  try {
    const h = (await fetch(location.href, { method: 'HEAD' })).headers;
    ['server', 'x-powered-by', 'x-vercel-id', 'cf-ray', 'x-nf-request-id', 'via'].forEach(k => add(h.get(k), k + ':'));
  } catch {}

  console.table(r.length ? r : ['Нічого не знайдено']);
})();
