// The Refract gallery application: a hash-routed, dependency-free single page.
(function () {
  const DATA = window.REFRACT_DATA;
  const { categories, entries, showcase } = window.RefractCatalog;
  const { device, PLATFORMS } = window.RefractPreview;
  const { highlight, languageOf, escape } = window.RefractHighlight;

  const cases = new Map(DATA.cases.map((entry) => [entry.path, entry]));
  const app = document.getElementById('app');

  // ------------------------------------------------------------------ i18n
  const STRINGS = {
    en: {
      navOverview: 'Overview',
      navComponents: 'Components',
      navReference: 'Mapping reference',
      navFixtures: 'Fixtures',
      navDiagnostics: 'Diagnostics',
      navAdopt: 'Get started',
      heroTitle: 'Write SwiftUI once.<br>Ship native Compose and ArkUI.',
      heroBody:
        'Refract reads screens written in a subset of SwiftUI and generates idiomatic Jetpack Compose and ArkUI source at build time. On iOS the same file is ordinary SwiftUI. No runtime, no bridge, no view-tree interpreter.',
      heroCta: 'Browse components',
      heroCta2: 'Adopt one screen',
      status: 'Early development, not production-ready.',
      oneSource: 'One source, three native outputs',
      oneSourceBody:
        'This is the settings screen the example apps adopt. The Swift file on the left is the only thing a developer writes; the Kotlin and ArkTS on the right are the golden expected output, byte for byte.',
      illustrative:
        'Illustrative renderings styled after each platform’s native toolkit — not screenshots. The code panels show the real generator output.',
      goals: 'Five goals every change must keep',
      allCategories: 'All',
      previewOn: 'Preview on',
      searchComponents: 'Filter components…',
      allComponents: 'All components',
      noMatch: 'No matching components.',
      swiftSource: 'SwiftUI source',
      composeOut: 'Jetpack Compose',
      arkuiOut: 'ArkUI',
      previews: 'How it looks',
      code: 'Code',
      sideBySide: 'Side by side',
      tabs: 'Tabs',
      notes: 'Notes',
      rejected: 'Rejected forms',
      rejectedBody: 'Constructs the generator refuses, with the exact build-time diagnostic it must report.',
      related: 'More fixtures',
      fixture: 'Fixture',
      openFixture: 'Open fixture',
      copy: 'Copy',
      copied: 'Copied',
      groupSwift: 'Swift',
      groupKotlin: 'Kotlin · Compose',
      groupArkTS: 'ArkTS · ArkUI',
      groupNative: 'Native host code',
      groupMapping: 'refract.json',
      groupStrings: 'String resources',
      groupDiagnostics: 'Diagnostics',
      groupOther: 'Other files',
      reference: 'Mapping reference',
      referenceBody: 'Generated from docs/subset.md, the conformance contract. Each row shows the accepted SwiftUI form and the native form an expert would write.',
      filter: 'Filter…',
      fixtures: 'Golden fixtures',
      fixturesBody: 'Every case in Fixtures/Corpus.json. Accepted cases carry expected Kotlin and ArkTS; rejected cases carry the expected diagnostics.',
      all: 'All',
      accepted: 'Accepted',
      rejectedShort: 'Rejected',
      pending: 'pending',
      diagnostics: 'Diagnostics',
      diagnosticsBody: 'Unsupported input is a build-time error that names the construct, explains why and suggests an alternative — never approximate code.',
      suggestion: 'Suggestion',
      binaries: 'Binary files (not shown)',
      notFound: 'Not found',
      back: 'Back',
      builtFrom: 'Built from',
      ios: 'iOS',
    },
    zh: {
      navOverview: '概览',
      navComponents: '组件',
      navReference: '映射参考',
      navFixtures: 'Fixtures',
      navDiagnostics: '诊断',
      navAdopt: '接入指南',
      heroTitle: '写一次 SwiftUI，<br>生成原生 Compose 与 ArkUI。',
      heroBody:
        'Refract 读取用 SwiftUI 子集写的界面，在构建期生成地道的 Jetpack Compose 和 ArkUI 源码；iOS 上同一个文件就是普通的 SwiftUI。没有运行时、没有桥接、没有视图树解释器。',
      heroCta: '浏览组件',
      heroCta2: '接入一个页面',
      status: '项目处于早期开发阶段，尚不可用于生产。',
      oneSource: '一份源码，三端原生产物',
      oneSourceBody:
        '下面是示例应用接入的设置页。左侧的 Swift 文件是开发者唯一要写的代码；右侧的 Kotlin 和 ArkTS 是 golden 期望产物，逐字节一致。',
      illustrative: '示意渲染：按各平台原生组件风格绘制，不是截图。代码面板展示的是真实的生成结果。',
      goals: '每个改动都必须守住的五条目标',
      allCategories: '全部',
      previewOn: '预览平台',
      searchComponents: '筛选组件…',
      allComponents: '全部组件',
      noMatch: '没有匹配的组件。',
      swiftSource: 'SwiftUI 源码',
      composeOut: 'Jetpack Compose',
      arkuiOut: 'ArkUI',
      previews: '各端效果',
      code: '代码',
      sideBySide: '并排',
      tabs: '标签页',
      notes: '说明',
      rejected: '会被拒绝的写法',
      rejectedBody: '生成器拒绝的写法，以及它在构建期必须给出的诊断信息。',
      related: '更多用例',
      fixture: '用例',
      openFixture: '查看用例',
      copy: '复制',
      copied: '已复制',
      groupSwift: 'Swift',
      groupKotlin: 'Kotlin · Compose',
      groupArkTS: 'ArkTS · ArkUI',
      groupNative: '原生宿主代码',
      groupMapping: 'refract.json',
      groupStrings: '字符串资源',
      groupDiagnostics: '诊断',
      groupOther: '其他文件',
      reference: '映射参考',
      referenceBody: '由一致性契约 docs/subset.md 自动生成。每一行给出支持的 SwiftUI 写法，以及资深工程师会手写的原生写法。',
      filter: '筛选…',
      fixtures: 'Golden fixtures',
      fixturesBody: 'Fixtures/Corpus.json 中的全部用例。通过的用例带有期望的 Kotlin 和 ArkTS；被拒绝的用例带有期望的诊断。',
      all: '全部',
      accepted: '通过',
      rejectedShort: '拒绝',
      pending: '待实现',
      diagnostics: '诊断',
      diagnosticsBody: '不支持的输入会在构建期报错：指出具体写法、说明原因并给出替代方案，绝不生成近似代码。',
      suggestion: '建议',
      binaries: '二进制文件（不展示）',
      notFound: '未找到',
      back: '返回',
      builtFrom: '构建自',
      ios: 'iOS',
    },
  };

  let lang = localStorage.getItem('refract.lang') || (navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en');
  let platform = localStorage.getItem('refract.platform') || 'ios';
  let codeLayout = localStorage.getItem('refract.codeLayout') || 'split';
  const s = (key) => STRINGS[lang][key] ?? STRINGS.en[key] ?? key;
  const L = (value) => (value && typeof value === 'object' ? value[lang] ?? value.en : value);

  // ------------------------------------------------------------------ helpers
  function inline(text) {
    // Minimal Markdown for table cells and notes: `code`, **bold**, [label](url).
    return escape(text)
      .replace(/\\\|/g, '|')
      .replace(/`([^`]+)`/g, '<code>$1</code>')
      .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1');
  }

  function codeBlock(content, lang, name) {
    return `<div class="code"><div class="code-head"><span>${escape(name ?? '')}</span><button class="copy" data-copy>${s('copy')}</button></div><pre><code>${highlight(content.replace(/\n$/, ''), lang)}</code></pre></div>`;
  }

  function groupFiles(fixture) {
    const groups = [
      { id: 'swift', label: s('groupSwift'), files: [] },
      { id: 'kotlin', label: s('groupKotlin'), files: [] },
      { id: 'arkts', label: s('groupArkTS'), files: [] },
      { id: 'diagnostics', label: s('groupDiagnostics'), files: [] },
      { id: 'native', label: s('groupNative'), files: [] },
      { id: 'mapping', label: s('groupMapping'), files: [] },
      { id: 'strings', label: s('groupStrings'), files: [] },
      { id: 'other', label: s('groupOther'), files: [] },
    ];
    const by = Object.fromEntries(groups.map((group) => [group.id, group]));
    for (const file of fixture.files) {
      const base = file.name.split('/').pop();
      if (file.name.endsWith('.swift')) by.swift.files.push(file);
      else if (/^Expected.*\.kt$/.test(file.name)) by.kotlin.files.push(file);
      else if (/^Expected.*\.ets$/.test(file.name)) by.arkts.files.push(file);
      else if (file.name.endsWith('.diagnostics')) by.diagnostics.files.push(file);
      else if (/\.(kt|ets)$/.test(file.name)) by.native.files.push(file);
      else if (base === 'refract.json') by.mapping.files.push(file);
      else if (/strings?\.(xml|json)$/.test(base)) by.strings.files.push(file);
      else by.other.files.push(file);
    }
    // Multi-file cases keep a placeholder Input.swift anchor; show the real sources first.
    by.swift.files.sort((a, b) => (a.name === 'Input.swift' ? 1 : b.name === 'Input.swift' ? -1 : a.name.localeCompare(b.name)));
    return groups.filter((group) => group.files.length);
  }

  let panelSeq = 0;
  function filePanel(group, extraClass = '') {
    const id = `fp${panelSeq++}`;
    const chips =
      group.files.length > 1
        ? `<div class="file-chips">${group.files
            .map((file, index) => `<button class="chip${index === 0 ? ' active' : ''}" data-file-tab="${id}" data-index="${index}">${escape(file.name)}</button>`)
            .join('')}</div>`
        : '';
    const bodies = group.files
      .map((file, index) => `<div class="file-body${index === 0 ? '' : ' hidden'}" data-file-body="${id}" data-index="${index}">${codeBlock(file.content, languageOf(file.name), file.name)}</div>`)
      .join('');
    return `<div class="file-panel ${extraClass}">${chips}${bodies}</div>`;
  }

  function codeTabs(groups, initial) {
    const id = `ct${panelSeq++}`;
    const start = Math.max(0, groups.findIndex((group) => group.id === initial));
    return `<div class="code-tabs">
      <div class="tabbar">${groups
        .map((group, index) => `<button class="tab${index === start ? ' active' : ''}" data-tab="${id}" data-index="${index}">${escape(group.label)}${group.files.length > 1 ? ` <span class="count">${group.files.length}</span>` : ''}</button>`)
        .join('')}</div>
      ${groups.map((group, index) => `<div class="tab-body${index === start ? '' : ' hidden'}" data-tab-body="${id}" data-index="${index}">${filePanel(group)}</div>`).join('')}
    </div>`;
  }

  // Swift on the left; Kotlin, ArkTS and the rest as tabs on the right. Or everything as tabs.
  function codeSection(fixture, options = {}) {
    const groups = groupFiles(fixture);
    const toggle = `<div class="seg" role="group">
      <button class="${codeLayout === 'split' ? 'active' : ''}" data-layout="split">${s('sideBySide')}</button>
      <button class="${codeLayout === 'tabs' ? 'active' : ''}" data-layout="tabs">${s('tabs')}</button>
    </div>`;
    const swift = groups.find((group) => group.id === 'swift');
    const rest = groups.filter((group) => group.id !== 'swift');
    const body =
      codeLayout === 'split' && swift && rest.length
        ? `<div class="code-split"><div>${codeTabs([swift], 'swift')}</div><div>${codeTabs(rest, rest[0].id)}</div></div>`
        : codeTabs(groups, 'swift');
    return `<div class="section-head${options.bare ? ' bare' : ''}">${options.bare ? '<span></span>' : `<h2>${s('code')}</h2>`}${toggle}</div>${body}`;
  }

  function platformSwitch() {
    return `<div class="seg" role="group" aria-label="${s('previewOn')}">${PLATFORMS.map(
      (p) => `<button class="${platform === p.id ? 'active' : ''}" data-platform="${p.id}">${p.name}</button>`,
    ).join('')}</div>`;
  }

  // A soft gradient stage with the three platform previews, each under a small floating label.
  function devices(spec, options = {}) {
    return `<div class="stage${options.large ? ' large' : ''}">
      <div class="stage-dots" aria-hidden="true"><i></i><i></i><i></i></div>
      <div class="stage-row">${PLATFORMS.map(
        (p) => `<figure class="stage-item"><figcaption><span class="dot ${p.id}"></span>${p.name}<span class="stage-kit">${p.toolkit}</span></figcaption>${device(spec, p.id)}</figure>`,
      ).join('')}</div>
    </div><p class="disclaimer">${s('illustrative')}</p>`;
  }

  function diagnosticItem(fixture) {
    const input = fixture.files.find((file) => file.name === 'Input.swift');
    return fixture.diagnostics
      .map((d) => {
        const lines = input ? input.content.split('\n') : [];
        const from = Math.max(0, d.line - 3);
        const excerpt = lines.slice(from, d.line + 1);
        const snippet = excerpt
          .map((line, index) => {
            const number = from + index + 1;
            const mark = number === d.line;
            return `<span class="ln${mark ? ' mark' : ''}"><span class="n">${number}</span>${highlight(line, 'swift')}</span>`;
          })
          .join('');
        return `<article class="diag">
          <header><span class="code-badge">${escape(d.code)}</span><a href="#/fixtures/${encodeURIComponent(fixture.path)}">${escape(fixture.path)}</a><span class="where">${escape(d.file)}:${d.line}:${d.column}</span></header>
          <p class="diag-msg">${inline(d.message)}</p>
          ${d.suggestion ? `<p class="diag-sug"><strong>${s('suggestion')}:</strong> ${inline(d.suggestion)}</p>` : ''}
          ${snippet ? `<pre class="diag-src"><code>${snippet}</code></pre>` : ''}
        </article>`;
      })
      .join('');
  }

  function fixtureLink(path) {
    const fixture = cases.get(path);
    if (!fixture) return '';
    return `<a class="pill ${fixture.kind}" href="#/fixtures/${encodeURIComponent(path)}">${escape(path)}</a>`;
  }

  // ------------------------------------------------------------------ pages
  const SHOWCASES = [
    { id: 'settings', en: 'Settings', zh: '设置页', fixture: showcase.fixture, preview: showcase.preview },
    ...['tabs', 'form', 'chat', 'markdown'].map((id) => {
      const entry = entries.find((e) => e.id === id);
      const labels = { tabs: ['Tabs & menu', '标签页与菜单'], form: ['Form', '表单'], chat: ['Messages', '消息列表'], markdown: ['Rich text', '富文本'] }[id];
      return { id, en: labels[0], zh: labels[1], fixture: entry.fixture, preview: entry.preview, entry: id };
    }),
  ];
  let showcaseId = 'settings';

  function display(first, second) {
    return `<h2 class="display"><span>${first}</span><span class="display-2">${second}</span></h2>`;
  }

  function overview() {
    const zh = lang === 'zh';
    const current = SHOWCASES.find((item) => item.id === showcaseId) ?? SHOWCASES[0];
    const fixture = cases.get(current.fixture);
    const goals = [
      { en: ['One source', 'A screen is written once; iOS, Android and HarmonyOS change together.'], zh: ['一份源码', '页面只写一次，iOS、Android、HarmonyOS 同步变化。'] },
      { en: ['Zero runtime', 'Only platform SDK calls in the output; never slower than hand-written code.'], zh: ['零运行时', '产物里只有平台 SDK 调用，性能不低于手写代码。'] },
      { en: ['Compile time only', 'Reviewed, deterministic output; unsupported input is a build error.'], zh: ['只在编译期', '产物确定、可审查；不支持的写法直接构建报错。'] },
      { en: ['One screen at a time', 'Adopt inside an existing app and switch back whenever you like.'], zh: ['逐页接入', '在现有应用里一页一页接入，随时可以切回。'] },
      { en: ['Mixes with native', 'Embed native views inside; call generated screens from native code.'], zh: ['与原生混用', '内部可嵌原生视图，生成的页面也能被原生调用。'] },
    ];
    const featured = ['toggle', 'textfield', 'list-section', 'tabs', 'navigation', 'native-view'].map((id) => entries.find((e) => e.id === id));
    const steps = [
      { en: ['Write', 'A screen in the SwiftUI subset, with a model protocol for data.'], zh: ['编写', '用 SwiftUI 子集写页面，数据通过 model 协议传入。'], code: 'struct SettingsScreen: View {\n    let model: SettingsModel\n    var body: some View { … }\n}', lang: 'swift' },
      { en: ['Generate', 'Kotlin and ArkTS at build time; commit and review them.'], zh: ['生成', '构建期生成 Kotlin 和 ArkTS，提交入库并评审。'], code: 'refract generate \\\n  --input SettingsScreen.swift \\\n  --mapping refract.json', lang: 'shell' },
      { en: ['Call', 'From your native navigation, like any other component.'], zh: ['调用', '在原生导航里调用，和普通组件一样。'], code: 'SettingsScreen(\n    model = model,\n    notificationsEnabled = enabled,\n    onNotificationsEnabledChange = { … },\n)', lang: 'kotlin' },
    ];
    return `
      <section class="hero">
        <p class="kicker">${zh ? '面向 Android 与 HarmonyOS 的编译期 SwiftUI' : 'Compile-time SwiftUI for Android and HarmonyOS'}</p>
        <h1 class="display hero-title"><span>${zh ? '写一次 SwiftUI，' : 'Write SwiftUI once.'}</span><span class="display-2">${zh ? '三端都是原生。' : 'Ship native everywhere.'}</span></h1>
        <p class="sub">${zh ? 'Refract 在构建期把 SwiftUI 子集转换成地道的 Jetpack Compose 和 ArkUI 代码，iOS 直接把同一个文件当普通 SwiftUI 编译。没有运行时，没有桥接。' : 'Refract turns a subset of SwiftUI into idiomatic Jetpack Compose and ArkUI at build time. iOS compiles the same file as ordinary SwiftUI. No runtime, no bridge.'}</p>
        <div class="hero-actions"><a class="pill-btn primary" href="#/components">${s('heroCta')}</a><a class="pill-btn" href="#/adopt">${s('heroCta2')}</a></div>
      </section>
      <section class="showcase">
        ${devices(current.preview, { large: true })}
        <div class="under-tabs" role="tablist">${SHOWCASES.map(
          (item) => `<button role="tab" class="${item.id === current.id ? 'active' : ''}" data-showcase="${item.id}">${escape(L(item))}</button>`,
        ).join('')}</div>
        ${current.entry ? `<div class="center"><a class="pill-btn small" href="#/components/${current.entry}">${zh ? '查看组件' : 'View component'}</a></div>` : ''}
      </section>
      <section class="block">
        <p class="kicker">${zh ? '原则' : 'Principles'}</p>
        <p class="center"><span class="soft-chip warning">${s('status')}</span></p>
        ${display(zh ? '五条目标，' : 'Five goals.', zh ? '每个改动都要守住。' : 'Every change keeps them.')}
        <ol class="goals">${goals
          .map((goal, index) => `<li class="goal"><span class="goal-n">0${index + 1}</span><h3>${L(goal)[0]}</h3><p>${L(goal)[1]}</p></li>`)
          .join('')}</ol>
      </section>
      <section class="block">
        <p class="kicker">${zh ? '生成代码' : 'Generated code'}</p>
        ${display(zh ? '一个 Swift 文件，' : 'One Swift file.', zh ? '逐字节对应的 Kotlin 与 ArkTS。' : 'Kotlin and ArkTS, byte for byte.')}
        <p class="sub">${zh ? '右侧是生成器必须逐字节复现的 golden 期望产物，跟随上方选中的示例切换。' : 'The right-hand side is the golden output the generator must reproduce exactly. It follows the example selected above.'}</p>
        ${fixture ? codeSection(fixture, { bare: true }) : ''}
      </section>
      <section class="block">
        <p class="kicker">${s('navComponents')}</p>
        ${display(zh ? '每个平台都是原生组件，' : 'Native on every platform.', zh ? '构建期就完成校验。' : 'Verified at build time.')}
        <p class="sub">${zh ? '每个组件都对应真实的 golden 用例：输入、两端期望产物，以及会被拒绝的写法。' : 'Every component is pinned by real golden fixtures: the input, both expected outputs and the forms that are rejected.'}</p>
        <div class="tiles">${featured.map(tile).join('')}</div>
        <div class="center"><a class="pill-btn" href="#/components">${s('allComponents')}</a></div>
      </section>
      <section class="block">
        <p class="kicker">${zh ? '接入' : 'Adoption'}</p>
        ${display(zh ? '一次接入一个页面，' : 'Adopt one screen.', zh ? '应用其他部分保持不变。' : 'Keep the rest of your app.')}
        <div class="steps3">${steps
          .map(
            (step, index) => `<div class="step3"><span class="goal-n">0${index + 1}</span><h3>${L(step)[0]}</h3><p>${L(step)[1]}</p><pre class="mini-code"><code>${highlight(step.code, step.lang)}</code></pre></div>`,
          )
          .join('')}</div>
        <div class="center"><a class="pill-btn" href="#/adopt">${zh ? '阅读接入指南' : 'Read the guide'}</a></div>
      </section>`;
  }

  function tile(entry) {
    return `<a class="tile" data-card data-search="${escape(entryHaystack(entry))}" href="#/components/${entry.id}">
      <div class="tile-preview">${device(entry.preview, platform, { compact: true })}</div>
      <div class="tile-foot"><span class="tile-title">${escape(entry.title)}</span><code class="tile-sig">${escape(entry.swiftui)}</code></div>
    </a>`;
  }

  // The persistent left-hand component list shared by the component index and every component page.
  let sidebarFilter = '';
  function entryHaystack(entry) {
    return [entry.title, entry.swiftui, entry.compose, entry.arkui, entry.summary.en, entry.summary.zh].join(' ').toLowerCase();
  }

  function sidebar(activeId, activeCategory) {
    return `<aside class="sidebar" data-sidebar>
      <input class="search side-search" type="search" placeholder="${s('searchComponents')}" value="${escape(sidebarFilter)}" data-sidebar-filter>
      <a class="side-all${!activeId && !activeCategory ? ' active' : ''}" href="#/components">${s('allComponents')}<span>${entries.length}</span></a>
      ${categories
        .map((cat) => {
          const items = entries.filter((entry) => entry.category === cat.id);
          return `<div class="side-group" data-side-group>
            <a class="side-cat${activeCategory === cat.id && !activeId ? ' active' : ''}" href="#/components?category=${cat.id}">${escape(L(cat))}</a>
            <ul>${items
              .map(
                (entry) => `<li><a class="side-item${entry.id === activeId ? ' active' : ''}" data-search="${escape(entryHaystack(entry))}" href="#/components/${entry.id}">${escape(entry.title)}</a></li>`,
              )
              .join('')}</ul>
          </div>`;
        })
        .join('')}
      <p class="side-empty hidden" data-side-empty>${s('noMatch')}</p>
    </aside>`;
  }

  function docsLayout(activeId, activeCategory, content) {
    return `<div class="docs">${sidebar(activeId, activeCategory)}<div class="docs-main">${content}</div></div>`;
  }

  // Filters the sidebar (and, on the index, the cards) in place, so typing never re-renders the page.
  function applySidebarFilter() {
    const needle = sidebarFilter.trim().toLowerCase();
    let any = false;
    document.querySelectorAll('[data-side-group]').forEach((group) => {
      let visible = 0;
      group.querySelectorAll('.side-item').forEach((item) => {
        const match = !needle || item.dataset.search.includes(needle);
        item.parentElement.classList.toggle('hidden', !match);
        if (match) visible++;
      });
      group.classList.toggle('hidden', visible === 0);
      if (visible) any = true;
    });
    document.querySelector('[data-side-empty]')?.classList.toggle('hidden', any);
    document.querySelectorAll('[data-grid-group]').forEach((group) => {
      let visible = 0;
      group.querySelectorAll('[data-card]').forEach((card) => {
        const match = !needle || card.dataset.search.includes(needle);
        card.classList.toggle('hidden', !match);
        if (match) visible++;
      });
      group.classList.toggle('hidden', visible === 0);
    });
  }

  function componentsPage(query) {
    const active = query.get('category') || '';
    const cat = categories.find((c) => c.id === active);
    const grouped = categories
      .filter((c) => !cat || c.id === cat.id)
      .map((c) => ({ cat: c, items: entries.filter((entry) => entry.category === c.id) }));
    const content = `
      <div class="page-head">
        <h1>${cat ? escape(L(cat)) : s('navComponents')}</h1>
        <div class="toolbar"><span class="muted small">${s('previewOn')}</span>${platformSwitch()}</div>
      </div>
      ${grouped
        .map(
          ({ cat: c, items }) => `<section data-grid-group>${cat ? '' : `<h2 class="cat-title">${escape(L(c))}</h2>`}<div class="tiles">${items
            .map(tile)
            .join('')}</div></section>`,
        )
        .join('')}`;
    return docsLayout(null, active, content);
  }

  function componentPage(id) {
    const index = entries.findIndex((entry) => entry.id === id);
    const entry = entries[index];
    if (!entry) return notFound();
    const fixture = cases.get(entry.fixture);
    const cat = categories.find((c) => c.id === entry.category);
    const prev = entries[index - 1];
    const next = entries[index + 1];
    const rejected = (entry.rejects ?? []).map((path) => cases.get(path)).filter(Boolean);
    const notes = L(entry.notes) ?? [];
    return `
      <header class="comp-head">
        <p class="kicker left">${escape(L(cat))}</p>
        <h1>${escape(entry.title)}</h1>
        <p class="lead">${escape(L(entry.summary))}</p>
        <div class="mapping">
          <div><span class="m-label"><span class="dot swift"></span>${s('swiftSource')}</span><code>${escape(entry.swiftui)}</code></div>
          <div><span class="m-label"><span class="dot android"></span>${s('composeOut')}</span><code>${escape(entry.compose)}</code></div>
          <div><span class="m-label"><span class="dot harmony"></span>${s('arkuiOut')}</span><code>${escape(entry.arkui)}</code></div>
        </div>
      </header>
      <section>
        <h2>${s('previews')}</h2>
        ${devices(entry.preview)}
      </section>
      <section>
        ${fixture ? codeSection(fixture) : ''}
        <p class="muted small">${s('fixture')}: ${fixtureLink(entry.fixture)}${(entry.related ?? []).length ? ` · ${s('related')}: ${entry.related.map(fixtureLink).join(' ')}` : ''}</p>
      </section>
      ${notes.length ? `<section><h2>${s('notes')}</h2><ul class="notes">${notes.map((note) => `<li>${inline(note)}</li>`).join('')}</ul></section>` : ''}
      ${rejected.length ? `<section><h2>${s('rejected')}</h2><p class="muted">${s('rejectedBody')}</p><div class="diags">${rejected.map(diagnosticItem).join('')}</div></section>` : ''}
      <nav class="pager">${prev ? `<a href="#/components/${prev.id}">← ${escape(prev.title)}</a>` : '<span></span>'}${next ? `<a href="#/components/${next.id}">${escape(next.title)} →</a>` : ''}</nav>`;
  }

  function componentDetail(id) {
    const entry = entries.find((e) => e.id === id);
    return docsLayout(entry ? entry.id : null, entry ? entry.category : '', componentPage(id));
  }

  function referencePage(query) {
    const filter = (query.get('q') || '').toLowerCase();
    return `
      <div class="page-head"><h1>${s('reference')}</h1><input class="search" type="search" placeholder="${s('filter')}" value="${escape(filter)}" data-reference-filter></div>
      <p class="muted">${s('referenceBody')}</p>
      ${DATA.subsetTables
        .map((table) => {
          const rows = table.rows.filter((row) => !filter || row.join(' ').toLowerCase().includes(filter));
          if (!rows.length) return '';
          return `<h2>${escape(table.heading)}</h2><div class="table-wrap"><table class="ref"><thead><tr>${table.columns.map((c) => `<th>${inline(c)}</th>`).join('')}</tr></thead><tbody>${rows
            .map((row) => `<tr>${row.map((cell) => `<td>${inline(cell)}</td>`).join('')}</tr>`)
            .join('')}</tbody></table></div>`;
        })
        .join('')}`;
  }

  function fixturesPage(query) {
    const kind = query.get('kind') || 'all';
    const filter = (query.get('q') || '').toLowerCase();
    const shown = DATA.cases.filter(
      (c) => (kind === 'all' || c.kind === kind) && (!filter || (c.path + ' ' + c.diagnostics.map((d) => d.code + ' ' + d.message).join(' ')).toLowerCase().includes(filter)),
    );
    const usedBy = new Map();
    for (const entry of entries) {
      for (const path of [entry.fixture, ...(entry.related ?? []), ...(entry.rejects ?? [])]) {
        if (!usedBy.has(path)) usedBy.set(path, entry);
      }
    }
    const kinds = [
      ['all', s('all'), DATA.cases.length],
      ['accepted', s('accepted'), DATA.cases.filter((c) => c.kind === 'accepted').length],
      ['rejected', s('rejectedShort'), DATA.cases.filter((c) => c.kind === 'rejected').length],
    ];
    return `
      <div class="page-head"><h1>${s('fixtures')}</h1><input class="search" type="search" placeholder="${s('filter')}" value="${escape(filter)}" data-fixture-filter></div>
      <p class="muted">${s('fixturesBody')}</p>
      <div class="cat-bar">${kinds.map(([id, label, n]) => `<a class="cat${kind === id ? ' active' : ''}" href="#/fixtures?kind=${id}">${label}<span>${n}</span></a>`).join('')}</div>
      <div class="fixture-list">${shown
        .map((c) => {
          const entry = usedBy.get(c.path);
          const meta = c.kind === 'rejected' ? c.diagnostics.map((d) => `<span class="code-badge">${escape(d.code)}</span>`).join(' ') : c.files.filter((f) => /\.(swift|kt|ets)$/.test(f.name)).length + ' files';
          return `<a class="fixture-row" href="#/fixtures/${encodeURIComponent(c.path)}"><span class="kind ${c.kind}">${c.kind === 'accepted' ? s('accepted') : s('rejectedShort')}</span><span class="path">${escape(c.path)}</span>${c.implementationStatus !== 'ready' ? `<span class="pending">${s('pending')}</span>` : ''}<span class="meta">${meta}</span>${entry ? `<span class="used">${escape(entry.title)}</span>` : ''}</a>`;
        })
        .join('')}</div>`;
  }

  function fixturePage(path) {
    const fixture = cases.get(path);
    if (!fixture) return notFound();
    const entry = entries.find((e) => e.fixture === path || (e.related ?? []).includes(path) || (e.rejects ?? []).includes(path));
    return `
      <nav class="crumbs"><a href="#/fixtures">${s('fixtures')}</a></nav>
      <header class="comp-head"><h1 class="mono">${escape(fixture.path)}</h1>
        <p><span class="kind ${fixture.kind}">${fixture.kind === 'accepted' ? s('accepted') : s('rejectedShort')}</span> ${fixture.implementationStatus !== 'ready' ? `<span class="pending">${s('pending')}</span>` : ''} ${entry ? ` <a href="#/components/${entry.id}">→ ${escape(entry.title)}</a>` : ''}</p>
      </header>
      ${fixture.kind === 'rejected' ? `<div class="diags">${diagnosticItem(fixture)}</div>` : ''}
      <section>${codeSection(fixture)}</section>
      ${fixture.binaries.length ? `<p class="muted small">${s('binaries')}: ${fixture.binaries.map((b) => `<code>${escape(b.name)}</code>`).join(' ')}</p>` : ''}`;
  }

  function diagnosticsPage(query) {
    const filter = (query.get('q') || '').toLowerCase();
    const byCode = new Map();
    for (const c of DATA.cases) {
      for (const d of c.diagnostics) {
        if (!byCode.has(d.code)) byCode.set(d.code, []);
        byCode.get(d.code).push({ c, d });
      }
    }
    const codes = [...byCode.keys()].sort();
    return `
      <div class="page-head"><h1>${s('diagnostics')}</h1><input class="search" type="search" placeholder="${s('filter')}" value="${escape(filter)}" data-diagnostic-filter></div>
      <p class="muted">${s('diagnosticsBody')}</p>
      <div class="table-wrap"><table class="ref diag-table"><tbody>${codes
        .flatMap((code) => {
          const rows = byCode.get(code).filter(({ c, d }) => !filter || `${code} ${c.path} ${d.message} ${d.suggestion}`.toLowerCase().includes(filter));
          return rows.map(
              ({ c, d }, index) =>
                `<tr>${index === 0 ? `<td rowspan="${rows.length}" class="code-cell"><span class="code-badge">${escape(code)}</span></td>` : ''}<td>${inline(d.message)}${d.suggestion ? `<div class="diag-sug"><strong>${s('suggestion')}:</strong> ${inline(d.suggestion)}</div>` : ''}</td><td>${fixtureLink(c.path)}</td></tr>`,
          );
        })
        .join('')}</tbody></table></div>`;
  }

  function adoptPage() {
    const zh = lang === 'zh';
    const step = (n, title, body) => `<section class="step"><div class="step-n">${n}</div><div class="step-body"><h2>${title}</h2>${body}</div></section>`;
    const p = (en, zhText) => `<p>${inline(zh ? zhText : en)}</p>`;
    const settings = cases.get('v0-settings-screen');
    const swift = settings.files.find((f) => f.name === 'Input.swift').content;
    const mapping = settings.files.find((f) => f.name === 'refract.json').content;
    return `
      <header class="comp-head"><h1>${s('navAdopt')}</h1>
        <p class="lead">${zh ? '在已有的原生应用里接入一个页面：导航、应用启动和数据层都保持手写，生成的页面就是一个普通的 Composable / ArkUI 组件。随时可以切回手写版本。' : 'Adopt one screen inside an existing native app. Navigation, start-up and the data layer stay hand-written; the generated screen is a plain Composable or ArkUI component, and you can switch back at any time.'}</p>
        <p class="status">${s('status')}</p>
      </header>
      ${step(
        1,
        zh ? '构建 Refract CLI' : 'Build the Refract CLI',
        p(
          'The CLI is a build-host tool only; nothing from it is linked into your app. Build it from a checkout with Swift 6, or produce a reproducible archive with `scripts/package_cli.py`. Integrations find it through `REFRACT_EXECUTABLE` or `PATH`.',
          'CLI 只在构建机上运行，不会被链接进应用。用 Swift 6 从源码构建，或用 `scripts/package_cli.py` 打出可复现的归档包。集成脚本通过 `REFRACT_EXECUTABLE` 或 `PATH` 找到它。',
        ) +
          codeBlock('swift build -c release\n.build/release/refract --version\n\n# or a local, checksummed archive for your build hosts\npython3 scripts/package_cli.py --output /tmp/refract-artifacts', 'shell', 'shell'),
      )}
      ${step(
        2,
        zh ? '用 SwiftUI 子集写页面' : 'Write the screen in the SwiftUI subset',
        p(
          'Data enters through a `RefractModel` protocol; parent-owned values are `@Binding`, local values are `@State`. String literals are localization keys. Anything outside the subset fails generation with a diagnostic — see the [Components](#/components) and [Mapping reference](#/reference).',
          '数据通过 `RefractModel` 协议传入；父级持有的值用 `@Binding`，本地值用 `@State`。字符串字面量是本地化 key。超出子集的写法会在生成时报诊断，可以对照「组件」和「映射参考」页面。',
        ) + codeBlock(swift, 'swift', 'SettingsScreen.swift'),
      )}
      ${step(
        3,
        zh ? '声明映射与字符串资源' : 'Declare the mapping and string resources',
        p(
          '`refract.json` tells each backend where generated files go, which R class and resource catalogs to validate against, and how tokens, symbols and design-system components map to your own code. Every key must exist in both `values/strings.xml` and `resources/base/element/string.json`.',
          '`refract.json` 告诉每个后端：产物输出到哪里、用哪个 R 类和资源目录做校验、token / 图标 / 设计系统组件如何映射到你自己的代码。每个 key 都必须同时存在于 `values/strings.xml` 和 `resources/base/element/string.json`。',
        ) + codeBlock(mapping, 'json', 'refract.json'),
      )}
      ${step(
        4,
        zh ? '生成并提交产物' : 'Generate and commit the output',
        p(
          'Generation validates every input, the mapping and the catalogs, then writes `.kt` and `.ets` atomically. Commit them and review them like product code; never hand-edit. `refract check` is the read-only CI form that fails when committed output is stale.',
          '生成过程会校验所有输入、映射和资源目录，然后原子地写出 `.kt` 和 `.ets`。把产物提交入库并像产品代码一样评审，不要手改。`refract check` 是只读的 CI 版本，产物过期时直接失败。',
        ) +
          codeBlock(
            'refract generate \\\n  --input Shared/SettingsScreen.swift \\\n  --mapping refract.json \\\n  --android-out app/src/main/java/refract/generated \\\n  --harmony-out entry/src/main/ets/generated\n\n# in CI\nrefract check --input Shared/SettingsScreen.swift --mapping refract.json \\\n  --android-out app/src/main/java/refract/generated \\\n  --harmony-out entry/src/main/ets/generated',
            'shell',
            'shell',
          ),
      )}
      ${step(
        5,
        zh ? '用现有模型实现生成的接口' : 'Implement the generated interface with your models',
        p(
          'The protocol becomes a Kotlin `interface` and an ArkTS `interface`. Your existing state implements it directly — Compose `State`, ArkUI `@ObservedV2` / `@Trace`. No adapter, no mirror.',
          'protocol 会生成为 Kotlin `interface` 和 ArkTS `interface`。现有状态直接实现即可（Compose 用 `State`，ArkUI 用 `@ObservedV2` / `@Trace`），不需要适配器或镜像。',
        ) +
          `<div class="two">${codeBlock(
            'class AppSettingsModel(initialTitle: String) : SettingsModel {\n    private val titleState = mutableStateOf(initialTitle)\n\n    override val title: State<String>\n        get() = titleState\n\n    override fun save() {\n        // The native application owns persistence and side effects.\n    }\n}',
            'kotlin',
            'AppSettingsModel.kt',
          )}${codeBlock(
            "import { SettingsModel } from '../generated/SettingsScreen';\n\n@ObservedV2\nexport class AppSettingsModel implements SettingsModel {\n  @Trace title: string;\n\n  constructor(title: string = 'Profile settings') {\n    this.title = title;\n  }\n\n  save(): void {\n    // The native application owns persistence and side effects.\n  }\n}",
            'ets',
            'AppSettingsModel.ets',
          )}</div>`,
      )}
      ${step(
        6,
        zh ? '在原生导航里调用（并可随时切回）' : 'Call it from native navigation — and switch back any time',
        p(
          'A generated screen is a public `@Composable` function or an exported `@ComponentV2` struct. Call it like any other; rolling back means calling the hand-written screen with the same arguments.',
          '生成的页面就是一个 public `@Composable` 函数或导出的 `@ComponentV2` 结构体，像其他组件一样调用即可；回滚就是用同样的参数调用手写版本。',
        ) +
          `<div class="two">${codeBlock(
            'if (useGeneratedSettings) {\n    SettingsScreen(\n        model = model,\n        notificationsEnabled = notificationsEnabled,\n        onNotificationsEnabledChange = { notificationsEnabled = it },\n    )\n} else {\n    HandWrittenSettingsScreen(\n        model = model,\n        notificationsEnabled = notificationsEnabled,\n        onNotificationsEnabledChange = { notificationsEnabled = it },\n    )\n}',
            'kotlin',
            'SettingsApp.kt',
          )}${codeBlock(
            'if (this.useGeneratedSettings) {\n  SettingsScreen({\n    model: this.model,\n    notificationsEnabled: this.notificationsEnabled,\n    onNotificationsEnabledChange: (value: boolean): void => {\n      this.notificationsEnabled = value;\n    }\n  })\n} else {\n  HandWrittenSettingsScreen({ /* same arguments */ })\n}',
            'ets',
            'GeneratedProfile.ets',
          )}</div>`,
      )}
      ${step(
        7,
        zh ? 'iOS：直接编译同一个文件' : 'iOS: compile the same file',
        p(
          'Add the same Swift file to your iOS target. A small source prelude (plain declarations such as `protocol RefractModel {}` and `RefractNativeView`, compiled only by the iOS target) makes the subset helpers ordinary SwiftUI. There is no Refract library to link.',
          '把同一个 Swift 文件加入 iOS target。再加一个很小的源码前置文件（只被 iOS target 编译的普通声明，如 `protocol RefractModel {}`、`RefractNativeView`），子集里的辅助写法就都是普通 SwiftUI 了。不需要链接任何 Refract 库。',
        ) + codeBlock('import SwiftUI\n\npublic protocol RefractModel {}\npublic protocol RefractNativeView: View {}\n// … see docs/interop.md, “The iOS source prelude”', 'swift', 'RefractSourcePrelude.swift'),
      )}
      ${step(
        8,
        zh ? '可选：SwiftPM 构建插件' : 'Optional: the SwiftPM build plugin',
        p(
          'A SwiftPM package can regenerate on every build with `RefractSwiftPMPlugin`. It takes explicit inputs and committed output directories, never scans directories and adds no library dependency to your target.',
          'SwiftPM 包可以通过 `RefractSwiftPMPlugin` 在每次构建时重新生成。它只接收显式列出的输入和已提交的输出目录，不扫描目录，也不会给 target 增加库依赖。',
        ) +
          `<div class="two">${codeBlock(
            '.target(\n    name: "RefractConsumer",\n    plugins: [.plugin(name: "RefractSwiftPMPlugin", package: "refract")]\n)',
            'swift',
            'Package.swift',
          )}${codeBlock(
            '{\n  "schemaVersion": 1,\n  "target": "RefractConsumer",\n  "sources": ["Sources/RefractConsumer/Hello.swift"],\n  "mapping": "Sources/RefractConsumer/refract.json",\n  "resourceInputs": [],\n  "androidOutput": "Generated/Android",\n  "harmonyOutput": "Generated/HarmonyOS"\n}',
            'json',
            'refract-swiftpm.json',
          )}</div>`,
      )}
      <section class="callout">
        <h3>${zh ? '仍然由原生代码负责的部分' : 'What stays native'}</h3>
        <ul class="notes">
          <li>${zh ? '应用入口、导航栈、返回处理与生命周期' : 'App entry points, navigation stacks, back handling and lifecycle'}</li>
          <li>${zh ? '数据层、网络、持久化和副作用' : 'The data layer, networking, persistence and side effects'}</li>
          <li>${zh ? '通过 RefractNativeView 嵌入的任意原生组件（地图、播放器、图片加载器……）' : 'Any native component embedded through RefractNativeView (maps, players, image loaders…)'}</li>
          <li>${zh ? '你的设计系统：token 与组件通过 refract.json 映射' : 'Your design system: tokens and components mapped through refract.json'}</li>
        </ul>
        <p class="muted small">${zh ? '详细文档' : 'Further reading'}: <code>docs/adoption.md</code> · <code>docs/interop.md</code> · <code>docs/mapping.md</code> · <code>docs/swiftpm-integration.md</code> · <code>docs/production-readiness.md</code></p>
      </section>`;
  }

  function notFound() {
    return `<div class="empty"><h1>${s('notFound')}</h1><a href="#/">${s('back')}</a></div>`;
  }

  // ------------------------------------------------------------------ shell & router
  function shell(route, content) {
    const nav = [
      ['#/', 'navOverview', ''],
      ['#/components', 'navComponents', 'components'],
      ['#/reference', 'navReference', 'reference'],
      ['#/fixtures', 'navFixtures', 'fixtures'],
      ['#/diagnostics', 'navDiagnostics', 'diagnostics'],
      ['#/adopt', 'navAdopt', 'adopt'],
    ];
    return `
      <header class="topbar"><div class="topbar-inner${route === 'components' ? ' wide' : ''}">
        <a class="brand" href="#/"><span class="logo" aria-hidden="true"></span>Refract</a>
        <nav class="mainnav">${nav.slice(1, 5).map(([href, key, id]) => `<a href="${href}" class="${route === id ? 'active' : ''}">${s(key)}</a>`).join('')}</nav>
        <div class="top-actions">
          <div class="seg lang" role="group"><button class="${lang === 'en' ? 'active' : ''}" data-lang="en">EN</button><button class="${lang === 'zh' ? 'active' : ''}" data-lang="zh">中文</button></div>
          <a class="pill-btn small raised${route === 'adopt' ? ' active' : ''}" href="#/adopt">${s('navAdopt')}</a>
        </div>
      </div></header>
      <main class="main${route === 'components' ? ' wide' : ''}">${content}</main>
      <footer class="footer">${s('builtFrom')} <code>Fixtures/Corpus.json</code> · <code>docs/subset.md</code>${DATA.revision ? ` · <code>${escape(DATA.revision)}</code>` : ''} · MIT</footer>`;
  }

  function parse() {
    const hash = location.hash.replace(/^#/, '') || '/';
    const [path, search] = hash.split('?');
    const parts = path.split('/').filter(Boolean).map(decodeURIComponent);
    return { parts, query: new URLSearchParams(search || '') };
  }

  let lastRoute = '';
  function renderRoute() {
    const { parts, query } = parse();
    const [first, ...rest] = parts;
    let content;
    switch (first) {
      case undefined:
        content = overview();
        break;
      case 'components':
        content = rest.length ? componentDetail(rest[0]) : componentsPage(query);
        break;
      case 'reference':
        content = referencePage(query);
        break;
      case 'fixtures':
        content = rest.length ? fixturePage(rest.join('/')) : fixturesPage(query);
        break;
      case 'diagnostics':
        content = diagnosticsPage(query);
        break;
      case 'adopt':
        content = adoptPage();
        break;
      default:
        content = notFound();
    }
    panelSeq = 0;
    const sidebarScroll = document.querySelector('[data-sidebar]')?.scrollTop;
    app.innerHTML = shell(first ?? '', content);
    const side = document.querySelector('[data-sidebar]');
    if (side) {
      applySidebarFilter();
      if (sidebarScroll != null) side.scrollTop = sidebarScroll;
      const current = side.querySelector('.side-item.active');
      if (current) {
        const top = current.offsetTop - side.scrollTop;
        if (top < 60 || top > side.clientHeight - 40) side.scrollTop = current.offsetTop - side.clientHeight / 3;
      }
    }
    document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
    const key = parts.join('/');
    if (key !== lastRoute) window.scrollTo(0, 0);
    lastRoute = key;
  }

  function setQuery(name, value) {
    const { parts, query } = parse();
    if (value) query.set(name, value);
    else query.delete(name);
    const search = query.toString();
    history.replaceState(null, '', `#/${parts.map(encodeURIComponent).join('/')}${search ? `?${search}` : ''}`);
  }

  // Filters re-render without losing focus or caret position.
  function rerenderKeepingFocus(selector) {
    const input = document.querySelector(selector);
    const caret = input ? input.selectionStart : null;
    renderRoute();
    const next = document.querySelector(selector);
    if (next) {
      next.focus();
      if (caret != null) next.setSelectionRange(caret, caret);
    }
  }

  document.addEventListener('click', (event) => {
    const target = event.target.closest('button');
    if (!target) return;
    if (target.dataset.showcase) {
      showcaseId = target.dataset.showcase;
      renderRoute();
    } else if (target.dataset.lang) {
      lang = target.dataset.lang;
      localStorage.setItem('refract.lang', lang);
      renderRoute();
    } else if (target.dataset.platform) {
      platform = target.dataset.platform;
      localStorage.setItem('refract.platform', platform);
      renderRoute();
    } else if (target.dataset.layout) {
      codeLayout = target.dataset.layout;
      localStorage.setItem('refract.codeLayout', codeLayout);
      renderRoute();
    } else if (target.dataset.tab) {
      const id = target.dataset.tab;
      document.querySelectorAll(`[data-tab="${id}"]`).forEach((el) => el.classList.toggle('active', el === target));
      document.querySelectorAll(`[data-tab-body="${id}"]`).forEach((el) => el.classList.toggle('hidden', el.dataset.index !== target.dataset.index));
    } else if (target.dataset.fileTab) {
      const id = target.dataset.fileTab;
      document.querySelectorAll(`[data-file-tab="${id}"]`).forEach((el) => el.classList.toggle('active', el === target));
      document.querySelectorAll(`[data-file-body="${id}"]`).forEach((el) => el.classList.toggle('hidden', el.dataset.index !== target.dataset.index));
    } else if (target.hasAttribute('data-copy')) {
      const code = target.closest('.code').querySelector('pre').innerText;
      navigator.clipboard?.writeText(code).then(() => {
        target.textContent = s('copied');
        setTimeout(() => (target.textContent = s('copy')), 1200);
      });
    }
  });

  const FILTERS = {
    '[data-reference-filter]': 'q',
    '[data-fixture-filter]': 'q',
    '[data-diagnostic-filter]': 'q',
  };
  document.addEventListener('input', (event) => {
    if (event.target.matches('[data-sidebar-filter]')) {
      sidebarFilter = event.target.value;
      applySidebarFilter();
      return;
    }
    for (const [selector, name] of Object.entries(FILTERS)) {
      if (event.target.matches(selector)) {
        setQuery(name, event.target.value);
        rerenderKeepingFocus(selector);
      }
    }
  });

  window.addEventListener('hashchange', renderRoute);
  renderRoute();
})();
