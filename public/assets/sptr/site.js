/* ==========================================================================
   SPTR marketing prototype — internal Marketing R&D build

   Everything here is local-only. No network calls, no analytics, no cookies.
   The variant and language choices live in localStorage so a reviewer can
   keep a cell open across reloads without re-typing the query string.
   ========================================================================== */
(function () {
  'use strict';

  var root = document.documentElement;
  var CONCEPTS = ['a', 'b', 'c'];
  var LANGS = ['en', 'ru'];

  /* ---- Russian message layer -------------------------------------------
     Localised as concept, not translated line by line. The three heroes in
     particular are separate stimuli in Russian and must be tested as such —
     a literal translation would be a different concept wearing the same
     label. English lives in the markup and is the no-JS fallback.
     ---------------------------------------------------------------------- */
  var RU = {
    brandSub: 'сокращённо от Spotter',
    navCta: 'Открыть прототип',

    heroEyebrow: 'Понятное оборудование',
    heroA: 'Тот тренажёр, мимо которого вы всё время проходите',
    heroB: 'Покажет, что прочитал.',
    heroC1: 'Навести.', heroC2: 'Узнать.', heroC3: 'Продолжить.',
    subA: 'Наведите телефон. SPTR поможет определить оборудование и покажет упражнения и инструкции, которые для него есть.',
    subB: 'Когда SPTR опирается на надпись с тренажёра, он показывает прочитанные слова рядом с ответом.',
    subC: 'Узнайте оборудование сейчас. А когда вернётесь к нему — получите обратно тренировку и настройки, которые сохранили для этого тренажёра.',
    ctaPrimary: 'Открыть прототип',
    ctaSecondary: 'Как это работает',
    heroCaption: 'Настоящая фотография, настоящий зал. Выше — кадр камеры, а не скриншот приложения.',

    s2Eyebrow: 'Механика',
    s2Title: 'Навели камеру — получили тренажёр.',
    s2Lede: 'Никаких наклеек на оборудовании. Никакой настройки со стороны зала. Работает с тем, что стоит перед вами.',
    s2aTitle: 'Навести',
    s2aBody: 'Нацельтесь на нужный тренажёр. SPTR читает надписи на нём и смотрит на сам тренажёр.',
    s2bTitle: 'Узнать',
    s2bBody: 'Отвечает из каталога на 69 типов оборудования — по-русски и по-английски, с теми названиями, которые люди реально используют.',
    s2cTitle: 'Сделать что-то на нём',
    s2cBody: '1 887 упражнений с шагами и видео, отфильтрованных по травмам, о которых вы сказали.',

    s3Eyebrow: 'Возвращение',
    s3Title: 'Второй раз должен быть проще первого.',
    s3Lede: 'Название тренажёра нужно один раз. На четвёртый визит важно другое — то, что никто не помнит: где было сиденье и сколько вы на самом деле подняли.',
    s3a: 'Сколько вы подняли на этом оборудовании в прошлый раз и когда.',
    s3b: 'Настройки, которые вы для него сохранили: сиденье, упор, штырь — или то, что на этом тренажёре вообще есть.',
    s3c: 'Подсказанный следующий вес, выведенный из того, как прошли последние подходы.',
    s3Prov: '<strong>SPTR не решает за вас, как настроить тренажёр.</strong> Он показывает то, что вы сохранили, и говорит, когда это было.',
    uiLast: 'В прошлый раз здесь',
    uiWhen: '2 недели назад · записали вы',
    uiSetup: 'Сохранённые настройки',
    uiSetupV: 'Сиденье 4 · упор 2',
    uiSetupM: 'сохранено вами 4 августа',
    illusNote: 'Иллюстрация будущей возможности — не скриншот и пока не построено.',

    s4Eyebrow: 'Основание',
    s4Title: 'Он показывает, что прочитал.',
    s4Lede: 'На многих тренажёрах написано их собственное название. Когда SPTR может опереться на эти слова, он выводит их рядом с ответом — проверка занимает секунду, и верить на слово не нужно.',
    proofCap: 'На тренажёре',
    uiRead: 'Прочитано на тренажёре',
    s4Restraint: 'А когда он не уверен, он так и пишет: <em>«Не уверен — самое похожее»</em> — и предлагает варианты, вместо того чтобы выбрать один и звучать уверенно.',
    s4Cap: 'Снято в настоящем зале, 30 июля 2026 года.',

    s5Eyebrow: 'Честная часть',
    s5Title: 'Никто не распознаёт всё. Поэтому он говорит, когда не знает.',
    s5Lede: 'Ответ, за который нельзя отвечать, хуже отсутствия ответа. Если тренажёр вне того, что SPTR знает, он так и скажет — и сохранит встречу, а не догадку.',
    s5aTitle: 'Говорит, что не знает',
    s5aBody: 'У тренажёра появляется своя карточка с пометкой <em>«Пока нет в каталоге»</em> и вашей фотографией.',
    s5bTitle: 'Считает, как часто он попадается',
    s5bBody: 'Встречи одного и того же тренажёра объединяются — <em>«сканировали 3 раза»</em> — и у пробела появляется размер, а не только имя.',
    s5cTitle: 'Пробелы задают очередь',
    s5cBody: 'Первым закрывается то оборудование, перед которым люди реально стоят. Без обещаний, когда именно.',

    s6Eyebrow: 'Прямо о данных',
    s6Title: 'Куда попадают ваши снимки — простыми словами.',
    s6aTitle: 'Фото прогресса остаются в телефоне',
    s6aBody: 'Зашифрованы на устройстве ключом из аппаратного хранилища и исключены из резервных копий.',
    s6bTitle: 'Снимки для распознавания уходят на распознавание',
    s6bBody: 'Фото тренажёра отправляется в Gemini от Google через Firebase. Это не на устройстве, и приложение об этом тоже говорит.',
    s6cTitle: 'На этой странице нет трекеров',
    s6cBody: 'Ни аналитики, ни сторонних скриптов, ни куки. Отсюда никуда ничего не уходит.',

    ctaTitle: 'SPTR делается открыто.',
    ctaBody: 'За ним нет компании и нечего покупать. Это одно Android-приложение на русском и английском, сделанное теми, кому надоело гадать, для чего этот тренажёр.',
    ctaBtn: 'Открыть прототип',
    ctaFine: 'В этой внутренней сборке ссылка на прототип не подключена.',

    footPrivacy: 'Конфиденциальность',
    footTerms: 'Условия',
    footNote: 'Внутренний R&D-прототип. Не публичная страница.'
  };

  /* ---- language --------------------------------------------------------- */
  var EN = null;

  function captureEnglish() {
    EN = {};
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      EN[el.dataset.i18n] = el.innerHTML;
    });
  }

  function applyLang(lang) {
    var dict = lang === 'ru' ? RU : EN;
    if (!dict) return;
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var v = dict[el.dataset.i18n];
      if (typeof v === 'string') el.innerHTML = v;
    });
    root.dataset.lang = lang;
    root.lang = lang;
    try { localStorage.setItem('sptr.lang', lang); } catch (e) { /* private mode */ }
    sync();
  }

  /* ---- concept ---------------------------------------------------------- */
  function applyConcept(c) {
    root.dataset.concept = c;
    try { localStorage.setItem('sptr.concept', c); } catch (e) { /* private mode */ }
    sync();
    log('concept', c);
  }

  function sync() {
    document.querySelectorAll('[data-set-concept]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.setConcept === root.dataset.concept));
    });
    document.querySelectorAll('[data-set-lang]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.setLang === root.dataset.lang));
    });
  }

  /* ---- local-only event log --------------------------------------------
     Kept in memory and echoed to the console. Deliberately never sent.
     ---------------------------------------------------------------------- */
  var events = [];
  function log(kind, value) {
    events.push({ kind: kind, value: value, at: performance.now() | 0 });
    if (root.dataset.debug) console.info('[sptr]', kind, value);
  }
  window.sptrEvents = function () { return events.slice(); };

  /* ---- boot ------------------------------------------------------------- */
  document.addEventListener('DOMContentLoaded', function () {
    captureEnglish();
    if (root.dataset.lang === 'ru') applyLang('ru');
    sync();

    // Brand reveal: SPOTTER collapses to SPTR once, shortly after load.
    var word = document.querySelector('.mark-word');
    var reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
    if (word) {
      if (reduce.matches) word.classList.add('tight');
      else requestAnimationFrame(function () { word.classList.add('tight'); });
    }

    // Scroll reveal.
    var targets = document.querySelectorAll(
      '.sec-head, .card, .split-copy, .split-media, .hero-copy, .hero-media, .fact, .wide-photo, .cta-in'
    );
    if (reduce.matches || !('IntersectionObserver' in window)) {
      targets.forEach(function (el) { el.classList.add('reveal', 'in'); });
    } else {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (!e.isIntersecting) return;
          e.target.classList.add('in');
          io.unobserve(e.target);
        });
      }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
      targets.forEach(function (el) { el.classList.add('reveal'); io.observe(el); });
    }

    // Debug controls.
    var panel = document.querySelector('.debug');
    if (panel && root.dataset.debug) {
      panel.hidden = false;
      panel.addEventListener('click', function (ev) {
        var b = ev.target.closest('button');
        if (!b) return;
        if (b.dataset.setConcept) applyConcept(b.dataset.setConcept);
        if (b.dataset.setLang) applyLang(b.dataset.setLang);
      });

      // The CSS badges show claim-state and public-gate; the qualification
      // condition itself is longer prose. A native `title` tooltip alone is
      // unreachable by keyboard, touch and much assistive tech (a11y review
      // finding), so this is a real focusable disclosure instead: a small
      // toggle button that reveals the qualify text as visible, selectable
      // page content rather than a hover-only tooltip.
      document.querySelectorAll('[data-claim-qualify]').forEach(function (el) {
        var toggle = document.createElement('button');
        toggle.type = 'button';
        toggle.className = 'qualify-toggle';
        toggle.setAttribute('aria-expanded', 'false');
        toggle.textContent = 'qualify ▾';

        var detail = document.createElement('span');
        detail.className = 'qualify-detail';
        detail.hidden = true;
        detail.textContent = el.dataset.claimQualify;

        toggle.addEventListener('click', function () {
          var open = toggle.getAttribute('aria-expanded') === 'true';
          toggle.setAttribute('aria-expanded', String(!open));
          toggle.textContent = open ? 'qualify ▾' : 'qualify ▴';
          detail.hidden = open;
        });

        el.append(' ', toggle, detail);
      });
    }

    // The prototype CTA has nowhere to go in an internal build. It still
    // records intent, locally, so a reviewer can see the click happened.
    var cta = document.querySelector('[data-cta]');
    if (cta) cta.addEventListener('click', function () { log('cta', root.dataset.concept); });

    log('view', root.dataset.concept + '/' + root.dataset.lang);
  });

  // Keep the visible cell honest if someone edits the query string by hand.
  window.addEventListener('popstate', function () {
    var p = new URLSearchParams(location.search);
    var c = (p.get('concept') || '').toLowerCase();
    if (CONCEPTS.indexOf(c) >= 0) applyConcept(c);
    var l = (p.get('lang') || '').toLowerCase();
    if (LANGS.indexOf(l) >= 0) applyLang(l);
  });
})();
