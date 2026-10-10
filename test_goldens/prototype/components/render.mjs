// Renders each prototype component on its own (paper and night) from v2.js's own functions.
// Run from the workspace with the app at app/: node app/test_goldens/prototype/components/render.mjs app/test_goldens/prototype/components [name]
import { launch, open } from '../../../../design/redesign/tools/_browser.mjs';
const out = process.argv[2], only = process.argv[3];
// name: [width, height, expression building the inner HTML (page context), selector to shoot]
const SPECS = {
  khatam: [390, 90, `'<div style="display:flex;gap:18px;align-items:center;padding:12px">' + khatam(56, '٢٢٦') + khatam(56, '١١', { fill: 'var(--lapis)', stroke: 'var(--lapis)', text: 'var(--bg)' }) + '<span style="background:var(--cover);border-radius:14px;padding:6px;display:inline-flex">' + khatam(48, '٤٢٪', { stroke: 'var(--gilt-on-cover)', ring: .42, text: 'var(--on-cover)' }) + '</span>' + khatam(26, '٢٢٩') + '</div>'`, '.shot > div'],
  gilt_rule: [390, 60, `'<div style="padding:8px 0"><div class="gilt-rule"></div><div class="gilt-rule mid"></div></div>'`, '.shot > div'],
  button: [390, 72, `'<div style="display:flex;gap:8px;padding:12px">' + '<button class="btn primary" type="button" style="flex:1.3">' + ic('play', 'f') + 'تشغيل الباب</button><button class="btn tonal" type="button" style="flex:1">' + ic('book') + 'الشرح</button></div>'`, '.shot > div'],
  stat_tile: [390, 90, `'<div class="stats" style="padding:12px">' + '<button class="stat" type="button"><b>١٫٢٥×</b><span class="t-cap">السرعة</span></button><button class="stat" type="button"><span class="badge">٢/٣</span><b>٣</b><span class="t-cap">تكرار البيت</span></button><button class="stat" type="button"><b>١</b><span class="t-cap">تكرار المقطع</span></button><button class="stat" type="button"><b>٢ ث</b><span class="t-cap">الفاصل</span></button></div>'`, '.shot > div'],
  min_segmented: [390, 68, `'<div style="padding:12px"><span class="minseg"><b>الصفحة</b><b class="on">النص</b></span></div>'`, '.shot > div'],
  switch: [390, 60, `'<div style="display:flex;gap:24px;padding:12px"><span class="toggle">تُتلى<i class="sw" role="switch" aria-checked="true"></i></span><span class="toggle">مخفي<i class="sw" role="switch" aria-checked="false"></i></span></div>'`, '.shot > div'],
  popover: [390, 150, `'<div class="pop" style="top:22px;--ax:120px"><i class="arrow" style="left:113px"></i><div class="t-label">البيت ٢٢٩</div><p class="t-cap" style="margin:4px 0 6px">نافذة تشير إلى ما فُتحت منه</p></div>'`, '.shot'],
  sheet: [390, 200, `'<div class="picker"><div class="grab"></div><div class="t-title" style="margin-top:10px">السرعة</div><div class="t-cap" style="font-size:13px;line-height:20px">تُحفظ لكل تلاوة على حدة.</div></div>'`, '.picker'],
  dock: [390, 4 * 140, `['playing','none','downloading','failed'].map((a, i) => '<div style="position:absolute;left:0;right:0;top:' + (i * 140) + 'px;height:140px">' + dock({ audio: a, verse: 229, playing: true }, 'المتن').replace('class="dock"', 'class="dock" style="bottom:12px"') + '</div>').join('')`, '.shot'],
  stepper: [390, 80, `'<div class="stepper" style="bottom:10px"><button type="button">' + ic('back') + 'البيت ٢٢٥</button><span class="mid">' + khatam(30, '١', { stroke: 'var(--gilt-on-cover)', text: 'var(--on-cover)' }) + 'من ٩ في الباب</span><button type="button">البيت ٢٢٧' + ic('fwd') + '</button></div>'`, '.stepper'],
  verse_unit: [390, 330, `'<div class="tm" style="padding:4px 12px">' + verseUnit(226) + verseUnit(229, { playing: true }) + verseUnit(230, { chosen: true }) + '</div>'`, '.tm'],
  symbol_frames: [390, 220, `'<div class="tm" style="padding:4px 12px">' + verseUnit(1027) + verseUnit(230, { playing: true }) + '</div>'`, '.tm'],
  chapter_head: [390, 170, `'<div class="tm" style="padding:0 12px">' + chapterHead(11, 'الباب الحادي عشر', 'بَابُ نَقْلِ حَرَكَةِ الْهَمْزَةِ إِلَى السَّاكِنِ قَبْلَهَا', 226, 234) + '</div>'`, '.tm'],
  matn_strip: [390, 290, `'<div style="padding:0 0 10px">' + matnStrip([226], 226) + matnStrip([230, 231, 232, 233], 231) + '</div>'`, '.shot > div'],
  snackbar: [390, 80, `'<div class="snack" role="status" style="bottom:14px;animation:none"><span>أُزيل المرجع: البيت ١٠٠١</span><button type="button">تراجع</button></div>'`, '.snack'],
};
const b = await launch();
const { page } = await open(b, { viewport: { width: 600, height: 900 }, deviceScaleFactor: 2, reducedMotion: 'reduce' });
for (const [name, [w, h, expr, sel]] of Object.entries(SPECS)) {
  if (only && name !== only) continue;
  for (const theme of ['light', 'dark']) {
    await page.evaluate(([w, h, expr, theme]) => {
      document.documentElement.setAttribute('data-theme', theme);
      let host = document.getElementById('shothost');
      if (!host) { host = document.createElement('div'); host.id = 'shothost'; document.body.appendChild(host); }
      host.style.cssText = 'position:fixed;left:0;top:0;z-index:99999';
      host.innerHTML = `<div class="app shot" style="position:relative;width:${w}px;height:${h}px">${eval(expr)}</div>`;
      host.querySelectorAll('.vu-t').forEach(() => {}); if (typeof fitHemistichs === 'function') fitHemistichs(host);
    }, [w, h, expr, theme]);
    await page.waitForTimeout(150);
    await page.locator('#shothost ' + sel).first().screenshot({ path: `${out}/${name}_${theme === 'light' ? 'paper' : 'night'}.png`, animations: 'disabled' });
  }
}
await b.close();
