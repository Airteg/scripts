// Markdown → PDF (KaTeX formulas, SVG figures) for the electrodynamics exam notes.
//
// Run it from the folder that holds the .md files; PDFs go to the PDF subfolder there
// (created if it does not exist):
//
//   cd D:\TEMP-forDelete\Електродинаміка-Екзамен\md_problems
//   node ..\convert_problems_to_pdf.cjs              all *.md → PDF\*.pdf + collection
//   node ..\convert_problems_to_pdf.cjs Z05.md       only the named files
//
// Collection («збірник») = one more PDF assembled from the same .md files:
// index.md as the table of contents, then every file from a new page
// (e.g. PDF\Електродинаміка_Z01-Z87.pdf). It is built only when no file names are given.
//
//   --no-collection   do not build the collection
//   --check           only check the layout, write nothing
//
// Fonts: DejaVu*.ttf from a pdf-fonts folder (current folder or next to the script) are
// embedded, so the PDFs look the same on any computer. Chrome path can be set via CHROME_PATH.

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { pathToFileURL } = require('node:url');
const { createRequire } = require('node:module');
const vm = require('node:vm');

const programFiles = process.env.ProgramFiles || 'C:/Program Files';
const SOURCE = process.cwd();
const OUTPUT = path.join(SOURCE, 'PDF');
const FONT_DIR = [path.join(SOURCE, 'pdf-fonts'), path.join(__dirname, 'pdf-fonts')]
  .find(dir => fs.existsSync(dir)) || path.join(__dirname, 'pdf-fonts');
const TOOLS_DIR = [path.join(__dirname, '.md-pdf-tools'), path.join(SOURCE, '.md-pdf-tools')]
  .find(dir => fs.existsSync(path.join(dir, 'node_modules', 'katex'))) || path.join(__dirname, '.md-pdf-tools');
const FONTS = [
  ['DejaVu Sans', 'normal', 'normal', 'DejaVuSans.ttf'],
  ['DejaVu Sans', 'bold', 'normal', 'DejaVuSans-Bold.ttf'],
  ['DejaVu Sans', 'normal', 'italic', 'DejaVuSans-Oblique.ttf'],
  ['DejaVu Sans', 'bold', 'italic', 'DejaVuSans-BoldOblique.ttf'],
  ['DejaVu Serif', 'normal', 'normal', 'DejaVuSerif.ttf'],
  ['DejaVu Serif', 'bold', 'normal', 'DejaVuSerif-Bold.ttf'],
  ['DejaVu Serif', 'normal', 'italic', 'DejaVuSerif-Italic.ttf'],
  ['DejaVu Serif', 'bold', 'italic', 'DejaVuSerif-BoldItalic.ttf']
];

function findChrome() {
  const candidates = [process.env.CHROME_PATH,
    path.join(programFiles, 'Google/Chrome/Application/chrome.exe'),
    path.join(process.env['ProgramFiles(x86)'] || 'C:/Program Files (x86)', 'Google/Chrome/Application/chrome.exe'),
    path.join(os.homedir(), 'AppData/Local/Google/Chrome/Application/chrome.exe'),
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome', '/usr/bin/chromium'];
  const found = candidates.find(candidate => candidate && fs.existsSync(candidate));
  if (!found) throw Error('Chrome not found. Set CHROME_PATH to chrome.exe.');
  return found;
}

function installedDirectory(parent, prefix, relativePath, knownDirectory) {
  let installed = [];
  try {
    installed = fs.readdirSync(parent).filter(name => name.startsWith(prefix)).sort().reverse();
  } catch (error) {
    if (!['ENOENT', 'EPERM', 'EACCES'].includes(error.code)) throw error;
  }
  return [...new Set(installed.concat(knownDirectory))]
    .map(name => path.join(parent, name, relativePath))
    .find(candidate => fs.existsSync(candidate));
}

function loadTools() {
  const localRequire = createRequire(path.join(TOOLS_DIR, 'convert.cjs'));
  if (fs.existsSync(path.join(TOOLS_DIR, 'node_modules', 'katex'))) {
    const katex = localRequire('katex');
    return {
      marked: localRequire('marked').marked,
      chromium: localRequire('playwright-core').chromium,
      katex,
      css: path.join(path.dirname(localRequire.resolve('katex')), 'katex.min.css')
    };
  }

  const runtimeModules = installedDirectory(path.join(programFiles, 'WindowsApps'),
    'OpenAI.CodexPrimaryRuntime.', 'dependencies/node/node_modules',
    'OpenAI.CodexPrimaryRuntime.v26-1119-907-0_26.1119.907.0_x64__3k8sg7r9htsxt');
  const vscode = path.join(os.homedir(), 'AppData/Local/Programs/Microsoft VS Code');
  const relativeMath = 'resources/app/extensions/markdown-math/notebook-out';
  const mathDir = installedDirectory(vscode, '', relativeMath, '8a14f0cc1b') ||
    path.join(vscode, relativeMath);
  if (!runtimeModules || !fs.existsSync(path.join(mathDir, 'katex.js'))) {
    throw Error('Install dependencies with: npm install --prefix .md-pdf-tools katex@0.16.21 marked playwright-core');
  }
  const runtimeRequire = createRequire(path.join(path.dirname(runtimeModules), 'convert.cjs'));
  const bundle = fs.readFileSync(path.join(mathDir, 'katex.js'), 'utf8');
  const katex = vm.runInNewContext(bundle.replace('import.meta.url', '"file:///katex.js"')
    .replace(/export\{xs as activate\};\s*$/, '') + '\nrn()');
  return {
    marked: runtimeRequire('marked').marked,
    chromium: runtimeRequire('playwright-core').chromium,
    katex,
    css: path.join(mathDir, 'katex.min.css')
  };
}

// ---------- styles (same layout as the question PDFs) ----------

function fontFaces() {
  const missing = FONTS.filter(font => !fs.existsSync(path.join(FONT_DIR, font[3])));
  if (missing.length) {
    console.warn('WARNING: pdf-fonts is missing ' + missing.map(font => font[3]).join(', ') +
      ' — system fonts will be used instead.');
  }
  return FONTS.filter(font => !missing.includes(font)).map(([family, weight, style, file]) =>
    '@font-face{font-family:"' + family + '";font-weight:' + weight + ';font-style:' + style +
    ';src:url("' + pathToFileURL(path.join(FONT_DIR, file)).href + '") format("truetype")}').join('');
}

const STYLE =
  '@page{size:A4}html{font:10pt/1.5 "DejaVu Sans",Verdana,sans-serif;color:#161616}' +
  'body{margin:0}h1,h2,h3{color:#161616;font-weight:bold;break-after:avoid;line-height:1.25}' +
  'h1{font-size:17pt;margin:0 0 .7em}h2{font-size:13.5pt;margin:1.2em 0 .5em}h3{font-size:11.5pt;margin:1.1em 0 .45em}' +
  'p{margin:.6em 0}blockquote{margin:.8em 0 1em;border-left:2px solid #aaa;padding:.1em .8em;color:#444}' +
  'blockquote p{margin:.2em 0}hr{border:0;border-top:1px solid #bbb;margin:1.2em 0}' +
  'ol,ul{padding-left:1.6em;margin:.4em 0 .6em}li{margin:.1em 0}' +
  'table{border-collapse:collapse;width:100%;margin:.6em 0 .9em}' +
  'th,td{border:1px solid #bbb;text-align:left;padding:3px 7px;vertical-align:top}th{background:#efefef;text-align:center}tr{break-inside:avoid}' +
  'td .katex{white-space:nowrap}' +
  '.katex{font-size:1.12em}.katex-display{margin:.6em 0}.display{break-inside:avoid}' +
  'code{font-family:"DejaVu Sans Mono",Consolas,monospace;font-size:.92em}' +
  'a{color:#0645ad}' +
  'img,svg.figure{display:block;max-width:100%;height:auto;margin:.6em auto .2em}' +
  'p:has(img),p:has(svg.figure){break-inside:avoid;break-after:avoid;margin-bottom:0}' +
  'section.doc{break-before:page}section.doc:first-child{break-before:auto}';

// ---------- markdown → html ----------

let svgCounter = 0;

// SVG figures are inlined (not <img>) so that their text uses the embedded DejaVu Serif.
// Every id inside one SVG gets a unique prefix: arrow markers have the same ids in all files.
function inlineSvg(file, alt) {
  const prefix = 'f' + (++svgCounter) + '-';
  let svg = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')
    .replace(/<\?xml[\s\S]*?\?>/g, '').replace(/<!DOCTYPE[\s\S]*?>/gi, '')
    .replace(/<metadata[\s\S]*?<\/metadata>/g, '').replace(/<!--[\s\S]*?-->/g, '').trim();
  svg = svg.replace(/\bid="([^"]+)"/g, (_, id) => 'id="' + prefix + id + '"')
    .replace(/url\(#([^)]+)\)/g, (_, id) => 'url(#' + prefix + id + ')')
    .replace(/(xlink:href|href)="#([^"]+)"/g, (_, attr, id) => attr + '="#' + prefix + id + '"');
  const label = alt.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
  return svg.replace(/^<svg\b/, '<svg class="figure" role="img" aria-label="' + label + '"');
}

function decodeHtml(text) {
  return text.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&amp;/g, '&');
}

function renderMarkdown(tools, file, ctx) {
  const { marked, katex } = tools;
  const dir = path.dirname(file);
  const md = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
  const start = ctx.formulas.length;
  const prepared = md.replace(/\$\$([\s\S]+?)\$\$|\$([^$\n]+)\$/g, (_, block, inline, offset) => {
    const displayMode = block !== undefined;
    const tex = (block ?? inline).trim().replace(/\\,(?=')/g, '');
    const token = 'ZFORMULAZ' + ctx.formulas.length + 'ZENDZ';
    try {
      ctx.formulas.push(katex.renderToString(tex, { displayMode, output: 'html', throwOnError: true }));
    } catch (error) {
      throw Error(path.basename(file) + ' line ' + md.slice(0, offset).split('\n').length + ': ' + error.message);
    }
    return displayMode ? '\n\n<div class="display">' + token + '</div>\n\n' : token;
  });
  let html = marked.parse(prepared).replace(/ZFORMULAZ(\d+)ZENDZ/g, (_, n) => ctx.formulas[Number(n)]);
  html = html.replace(/<img\s[^>]*>/g, tag => {
    const src = decodeHtml((tag.match(/\ssrc="([^"]*)"/) || [])[1] || '');
    const alt = decodeHtml((tag.match(/\salt="([^"]*)"/) || [])[1] || '');
    const target = path.resolve(dir, decodeURIComponent(src.split(/[?#]/)[0]));
    if (!fs.existsSync(target)) throw Error(path.basename(file) + ': image not found: ' + src);
    if (/\.svg$/i.test(target)) return inlineSvg(target, alt);
    return '<img alt="' + alt.replace(/"/g, '&quot;') + '" src="' + pathToFileURL(target).href + '">';
  });
  return { html, formulas: ctx.formulas.length - start,
    images: [...md.matchAll(/!\[[^\]]*\]\([^)]+\)/g)].length };
}

function htmlDocument(title, body, katexCss) {
  return '<!doctype html><html lang="uk"><meta charset="utf-8"><title>' + title + '</title>' +
    '<link rel="stylesheet" href="' + katexCss + '"><style>' + fontFaces() + STYLE + '</style>' +
    '<body>' + body + '</body></html>';
}

// ---------- layout check (also shrinks formulas that are too wide) ----------

async function layoutCheck(page) {
  return page.evaluate(async () => {
    await document.fonts.ready;
    const formulas = [...document.querySelectorAll('.katex')];
    const pageWidth = document.body.clientWidth;
    for (const table of document.querySelectorAll('table')) {
      if (table.offsetWidth > pageWidth) table.style.tableLayout = 'fixed';
    }
    for (const formula of formulas) {
      const cell = formula.closest('td,th');
      const available = cell ? cell.clientWidth - 12 : pageWidth;
      const content = formula.querySelector('.katex-html');
      if (!content) continue;
      const range = document.createRange();
      range.selectNodeContents(content);
      const width = range.getBoundingClientRect().width;
      if (width > available && available > 0) {
        formula.style.fontSize = (available / width * 1.01) + 'em';
      }
    }
    const images = [...document.images];
    const figures = [...document.querySelectorAll('svg.figure')];
    const wanted = ['DejaVu Sans', 'KaTeX_Main'];
    const loaded = [...document.fonts].filter(font => font.status === 'loaded').map(font => font.family.replace(/"/g, ''));
    return { formulas: formulas.length, images: images.length + figures.length,
      broken: images.filter(img => !img.naturalWidth).length +
        figures.filter(svg => !svg.getBoundingClientRect().width).length,
      fonts: loaded.length, missingFonts: formulas.length ? wanted.filter(f => !loaded.includes(f)) : [],
      overflow: document.documentElement.scrollWidth > pageWidth + 2 };
  });
}

function verify(check, expected) {
  if (check.formulas !== expected.formulas || check.images !== expected.images || check.broken ||
      check.missingFonts.length || check.overflow) {
    throw Error('Layout check failed: ' + JSON.stringify({
      expected: { formulas: expected.formulas, images: expected.images }, ...check }));
  }
}

function footer(label) {
  return '<div style="width:100%;text-align:center;font-size:8px;color:#222;' +
    'font-family:DejaVu Sans,Verdana,sans-serif">' + label +
    '<span class="pageNumber"></span> / <span class="totalPages"></span></div>';
}

async function writePdf(page, file, label) {
  const pdf = await page.pdf({
    preferCSSPageSize: true, printBackground: true, outline: true, tagged: true,
    margin: { top: '14mm', right: '14mm', bottom: '14mm', left: '14mm' },
    displayHeaderFooter: true, headerTemplate: '<div></div>', footerTemplate: footer(label)
  });
  fs.writeFileSync(file, pdf);
}

// ---------- main ----------

async function main() {
  const args = process.argv.slice(2);
  const flags = new Set(args.filter(arg => arg.startsWith('--')));
  const known = ['--check', '--no-collection'];
  const unknown = [...flags].filter(flag => !known.includes(flag));
  if (unknown.length) throw Error('Unknown option ' + unknown.join(' ') + '. Options: ' + known.join(' '));
  const checkOnly = flags.has('--check');
  const requested = args.filter(arg => !arg.startsWith('--'));
  for (const name of requested) {
    if (!/\.md$/i.test(name) || !fs.existsSync(path.join(SOURCE, name))) {
      throw Error('No such .md file in ' + SOURCE + ': ' + name);
    }
  }

  const all = fs.readdirSync(SOURCE).filter(name => /\.md$/i.test(name))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  const isIndex = name => /^index\.md$/i.test(name);
  const chapters = all.filter(name => !isIndex(name));
  if (!all.length) throw Error('No .md files in ' + SOURCE + ' — run the script from the folder with the .md files.');
  const names = requested.length ? requested : chapters.concat(all.filter(isIndex));
  const collection = !requested.length && !flags.has('--no-collection') && chapters.length > 1;

  const tools = loadTools();
  const katexCss = pathToFileURL(tools.css).href;
  if (!checkOnly) fs.mkdirSync(OUTPUT, { recursive: true });
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'md-pdf-'));
  const preview = path.join(temporary, 'preview.html');
  const code = name => name.replace(/\.md$/i, '');
  let browser;
  let failed = 0;
  let total = 0;
  try {
    browser = await tools.chromium.launch({
      executablePath: findChrome(), args: ['--allow-file-access-from-files']
    });
    const page = await browser.newPage({ viewport: { width: 688, height: 1100 } });
    await page.emulateMedia({ media: 'print' });

    // single files
    for (const name of names) {
      total++;
      try {
        const ctx = { formulas: [] };
        const result = renderMarkdown(tools, path.join(SOURCE, name), ctx);
        const label = isIndex(name) ? 'Зміст' : code(name);
        fs.writeFileSync(preview, htmlDocument(label, result.html, katexCss), 'utf8');
        await page.goto(pathToFileURL(preview).href, { waitUntil: 'load' });
        const check = await layoutCheck(page);
        verify(check, result);
        if (!checkOnly) await writePdf(page, path.join(OUTPUT, code(name) + '.pdf'), label + ' · ');
        console.log('OK ' + name + ' | math: ' + check.formulas + ' | images: ' + check.images);
      } catch (error) {
        failed++;
        console.error('ERROR ' + name + ' | ' + error.message);
      }
    }

    // collection: index.md as the table of contents, then every file from a new page
    if (collection) {
      total++;
      const bookName = 'Електродинаміка_' + code(chapters[0]) + '-' + code(chapters[chapters.length - 1]) + '.pdf';
      try {
        const ctx = { formulas: [] };
        const expected = { formulas: 0, images: 0 };
        const codes = new Set(chapters.map(code));
        const sections = [];
        const indexName = all.find(isIndex);
        if (indexName) {
          const toc = renderMarkdown(tools, path.join(SOURCE, indexName), ctx);
          expected.formulas += toc.formulas;
          expected.images += toc.images;
          // a table cell that holds just a file name (Q01, Z01) becomes a link to that section
          const html = toc.html.replace(/<td([^>]*)>\s*([^<>\s]+)\s*<\/td>/g, (cell, attrs, text) =>
            codes.has(text) ? '<td' + attrs + '><a href="#' + text + '">' + text + '</a></td>' : cell);
          sections.push('<section class="doc toc">' + html + '</section>');
        }
        for (const name of chapters) {
          const result = renderMarkdown(tools, path.join(SOURCE, name), ctx);
          expected.formulas += result.formulas;
          expected.images += result.images;
          sections.push('<section class="doc" id="' + code(name) + '">' + result.html + '</section>');
        }
        fs.writeFileSync(preview, htmlDocument(code(bookName), sections.join('\n'), katexCss), 'utf8');
        await page.goto(pathToFileURL(preview).href, { waitUntil: 'load' });
        const check = await layoutCheck(page);
        verify(check, expected);
        if (!checkOnly) await writePdf(page, path.join(OUTPUT, bookName), 'стор. ');
        console.log('OK ' + bookName + ' | sections: ' + chapters.length + ' | math: ' + check.formulas +
          ' | images: ' + check.images);
      } catch (error) {
        failed++;
        console.error('ERROR ' + bookName + ' | ' + error.message);
      }
    }
  } finally {
    if (browser) await browser.close();
    if (fs.existsSync(preview)) fs.unlinkSync(preview);
    fs.rmdirSync(temporary);
  }
  console.log((checkOnly ? 'Checked: ' : 'Done: ') + (total - failed) + '/' + total +
    (checkOnly ? '' : ' → ' + OUTPUT));
  process.exitCode = failed ? 1 : 0;
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
