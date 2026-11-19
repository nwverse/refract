// Illustrative three-platform previews.
//
// Each catalog entry describes its screen once with a tiny declarative spec. This renderer draws that spec three times,
// styled after SwiftUI on iOS, Material 3 (Jetpack Compose) on Android and ArkUI on HarmonyOS. The drawings follow the
// native component each backend emits (see the Expected.kt / Expected.ets of the linked fixture), but they are HTML
// approximations, not screenshots. The gallery labels them as such everywhere they appear.
(function () {
  const { escape } = window.RefractHighlight;

  const ICONS = {
    gear: 'M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Zm7.4-2.5a7.6 7.6 0 0 0 0-2l2-1.6-2-3.4-2.4 1a7.4 7.4 0 0 0-1.7-1L15 3.5h-4l-.4 2.5a7.4 7.4 0 0 0-1.7 1l-2.4-1-2 3.4 2 1.6a7.6 7.6 0 0 0 0 2l-2 1.6 2 3.4 2.4-1a7.4 7.4 0 0 0 1.7 1l.4 2.5h4l.4-2.5a7.4 7.4 0 0 0 1.7-1l2.4 1 2-3.4Z',
    person: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm-8 8c0-3.3 3.6-6 8-6s8 2.7 8 6',
    check: 'M5 12.5l4.5 4.5L19 7.5',
    chevron: 'M9 5l7 7-7 7',
    back: 'M15 5l-7 7 7 7',
    arrowBack: 'M20 12H5m6-7-7 7 7 7',
    more: 'M5 12h.01M12 12h.01M19 12h.01',
    moreVert: 'M12 5h.01M12 12h.01M12 19h.01',
    search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14Zm5-2 4 4',
    house: 'M4 11l8-7 8 7v9h-5v-6H9v6H4Z',
    bell: 'M6 16V11a6 6 0 0 1 12 0v5l2 2H4Zm4 3a2 2 0 0 0 4 0',
    star: 'M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.8-5.2-2.8-5.2 2.8 1-5.8-4.3-4.1 5.9-.8Z',
    photo: 'M4 5h16v14H4Zm0 11 5-5 4 4 3-3 4 4M15.5 9.5h.01',
    link: 'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1',
    doc: 'M7 3h7l5 5v13H7ZM14 3v5h5M10 13h6M10 17h6',
    eye: 'M2 12s3.5-6.5 10-6.5S22 12 22 12s-3.5 6.5-10 6.5S2 12 2 12Zm10 3a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z',
    plus: 'M12 5v14M5 12h14',
    globe: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Zm-9-9h18M12 3c2.5 2.5 3.8 5.5 3.8 9s-1.3 6.5-3.8 9c-2.5-2.5-3.8-5.5-3.8-9S9.5 5.5 12 3Z',
    list: 'M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01',
    copy: 'M9 9h11v11H9ZM5 15H4V4h11v1',
    send: 'M4 12l16-8-6 16-3-7Z',
    refresh: 'M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7',
    move: 'M12 3v18M3 12h18M12 3l-3 3m3-3 3 3m-3 15-3-3m3 3 3-3M3 12l3-3m-3 3 3 3m15-3-3-3m3 3-3 3',
  };

  function icon(name, size = 20) {
    const path = ICONS[name] ?? ICONS.star;
    return `<svg class="pv-icon" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${path}"/></svg>`;
  }

  const STATUS = {
    ios: '<span class="sb-time">9:41</span><span class="sb-island"></span><span class="sb-icons"><i class="sb-signal"></i><i class="sb-wifi"></i><i class="sb-battery"></i></span>',
    android: '<span class="sb-time">12:30</span><span class="sb-camera"></span><span class="sb-icons"><i class="sb-wifi"></i><i class="sb-signal"></i><i class="sb-battery"></i></span>',
    harmony: '<span class="sb-time">08:08</span><span class="sb-camera"></span><span class="sb-icons"><i class="sb-signal"></i><i class="sb-wifi"></i><i class="sb-battery"></i></span>',
  };

  const t = (value) => escape(String(value ?? ''));

  function children(nodes, p) {
    return (nodes ?? []).map((node) => render(node, p)).join('');
  }

  function stackStyle(node) {
    const style = [];
    if (node.gap != null) style.push(`gap:${node.gap}px`);
    if (node.pad != null) style.push(`padding:${node.pad}px`);
    return style.length ? ` style="${style.join(';')}"` : '';
  }

  function toggleControl(on, p) {
    return `<span class="pv-switch pv-switch-${p}${on ? ' on' : ''}" role="switch" aria-checked="${on ? 'true' : 'false'}"><span class="pv-thumb">${p === 'android' && on ? icon('check', 14) : ''}</span></span>`;
  }

  function field(node, p) {
    const value = node.value ?? '';
    const shown = node.secure && value ? (node.revealed ? value : '•'.repeat(Math.min(value.length, 12))) : value;
    if (p === 'ios') {
      return `<div class="pv-field pv-field-ios${node.inList ? ' in-list' : ''}">${shown ? `<span>${t(shown)}</span>` : `<span class="ph">${t(node.s)}</span>`}</div>`;
    }
    if (p === 'android') {
      const floating = Boolean(shown) || node.focused;
      return `<div class="pv-field pv-field-android${floating ? ' floating' : ''}${node.focused ? ' focused' : ''}"><span class="lbl">${t(node.s)}</span>${shown ? `<span class="val">${t(shown)}</span>` : ''}${node.secure ? `<span class="trail">${icon('eye', 18)}</span>` : ''}</div>`;
    }
    return `<div class="pv-field pv-field-harmony">${shown ? `<span>${t(shown)}</span>` : `<span class="ph">${t(node.s)}</span>`}${node.secure ? `<span class="trail">${icon('eye', 18)}</span>` : ''}</div>`;
  }

  function button(node, p, inList) {
    const content = `${node.icon ? icon(node.icon, 18) : ''}${node.s ? `<span>${t(node.s)}</span>` : ''}`;
    const disabled = node.disabled ? ' disabled' : '';
    if (p === 'ios') {
      // SwiftUI's default button style is borderless; inside a List it is a tinted text row.
      const kind = node.kind === 'prominent' ? 'pv-btn-ios-prominent' : inList ? 'pv-btn-ios-row' : 'pv-btn-ios-plain';
      return `<span class="pv-btn ${kind}${disabled}">${content}</span>`;
    }
    if (p === 'android') {
      // The Compose backend emits Material 3 Button: a filled, full-radius container.
      return `<span class="pv-btn pv-btn-android${disabled}">${content}</span>`;
    }
    // ArkUI Button() defaults to a filled capsule.
    return `<span class="pv-btn pv-btn-harmony${disabled}">${content}</span>`;
  }

  function list(node, p) {
    const sections = node.sections.map((section) => {
      const header = section.header ? `<div class="pv-list-header">${t(section.header)}</div>` : '';
      const rows = section.rows
        .map((row) => {
          if (row.t === 'button') return `<div class="pv-row pv-row-button">${button(row, p, true)}</div>`;
          if (row.t === 'field') return `<div class="pv-row">${field({ ...row, inList: true }, p)}</div>`;
          return `<div class="pv-row">${render(row, p)}</div>`;
        })
        .join('');
      return `<div class="pv-section">${header}<div class="pv-section-body">${rows}</div></div>`;
    });
    return `<div class="pv-list pv-list-${p}">${sections.join('')}</div>`;
  }

  function render(node, p) {
    if (typeof node === 'string') return `<span class="pv-text">${t(node)}</span>`;
    switch (node.t) {
      case 'text':
        return `<span class="pv-text pv-text-${node.style ?? 'body'}${node.tone ? ` tone-${node.tone}` : ''}"${node.styleAttr ? ` style="${node.styleAttr}"` : ''}>${t(node.s)}</span>`;
      case 'button':
        return button(node, p, false);
      case 'toggle':
        if (node.hideLabel) return toggleControl(node.on, p);
        return `<div class="pv-toggle-row"><span class="pv-text">${t(node.s)}</span><span class="pv-flex"></span>${toggleControl(node.on, p)}</div>`;
      case 'field':
        return field(node, p);
      case 'search':
        return `<div class="pv-search pv-search-${p}">${icon('search', 16)}<span class="${node.value ? '' : 'ph'}">${t(node.value || node.s)}</span></div>`;
      case 'vstack':
        return `<div class="pv-vstack align-${node.align ?? 'center'}"${stackStyle(node)}>${children(node.children, p)}</div>`;
      case 'hstack':
        return `<div class="pv-hstack align-${node.align ?? 'center'}"${stackStyle(node)}>${children(node.children, p)}</div>`;
      case 'zstack':
        return `<div class="pv-zstack align-${node.align ?? 'center'}"${stackStyle(node)}>${children(node.children, p)}</div>`;
      case 'scroll':
        return `<div class="pv-scroll"${stackStyle(node)}>${children(node.children, p)}<div class="pv-scrollbar"></div></div>`;
      case 'spacer':
        return '<span class="pv-flex pv-spacer"></span>';
      case 'divider':
        return '<hr class="pv-divider">';
      case 'label':
        return `<span class="pv-label">${icon(node.icon, 18)}<span>${t(node.s)}</span></span>`;
      case 'icon':
        return `<span class="pv-icon-wrap">${icon(node.name, node.size ?? 22)}</span>`;
      case 'list':
        return list(node, p);
      case 'navrow':
        return `<div class="pv-navrow"><span class="pv-text">${t(node.s)}</span><span class="pv-flex"></span>${node.detail ? `<span class="pv-text tone-secondary">${t(node.detail)}</span>` : ''}${p === 'android' ? '' : `<span class="pv-chevron">${icon('chevron', 14)}</span>`}</div>`;
      case 'native':
        return `<div class="pv-native"><span class="pv-native-tag">${t(node.tag ?? 'native')}</span><span class="pv-native-body">${node.icon ? icon(node.icon, 22) : ''}<span>${t(node.s)}</span></span>${node.sub ? `<span class="pv-native-sub">${t(node.sub[p] ?? node.sub)}</span>` : ''}</div>`;
      case 'image':
        return `<div class="pv-image" style="height:${node.h ?? 120}px">${icon(node.icon ?? 'photo', 32)}${node.s ? `<span>${t(node.s)}</span>` : ''}</div>`;
      case 'badge':
        return `<span class="pv-badge">${t(node.s)}</span>`;
      case 'card':
        return `<div class="pv-card"${stackStyle(node)}>${children(node.children, p)}</div>`;
      case 'bubble':
        return `<div class="pv-bubble-row${node.me ? ' me' : ''}"><div class="pv-bubble">${node.rich ? rich(node.rich) : t(node.s)}</div></div>`;
      case 'rich':
        return `<p class="pv-rich">${rich(node.parts)}</p>`;
      case 'codeblock':
        return `<pre class="pv-codeblock">${t(node.s)}</pre>`;
      case 'selection':
        return `<p class="pv-rich">${t(node.before)}<mark class="pv-selected">${t(node.selected)}</mark>${t(node.after)}</p><div class="pv-selection-menu pv-selection-menu-${p}">${node.actions.map((a) => `<span>${t(a)}</span>`).join('')}</div>`;
      case 'menu':
        return `<div class="pv-menu pv-menu-${p}">${node.items.map((item) => `<span class="pv-menu-item">${t(item)}</span>`).join('')}</div>`;
      case 'error':
        return `<span class="pv-text pv-text-caption tone-error">${t(node.s)}</span>`;
      case 'progress':
        return `<span class="pv-progress pv-progress-${p}"></span>`;
      case 'sheet':
        return `<div class="pv-sheet pv-sheet-${p}"><div class="pv-sheet-grip"></div>${children(node.children, p)}</div>`;
      case 'platform':
        return render(node[p], p);
      default:
        return '';
    }
  }

  function rich(parts) {
    return parts
      .map((part) => {
        if (typeof part === 'string') return t(part);
        if (part.b) return `<strong>${t(part.b)}</strong>`;
        if (part.i) return `<em>${t(part.i)}</em>`;
        if (part.code) return `<code>${t(part.code)}</code>`;
        if (part.link) return `<a>${t(part.link)}</a>`;
        return '';
      })
      .join('');
  }

  function navBar(nav, p) {
    if (!nav) return '';
    const trailing = nav.trailing ? `<span class="pv-nav-trailing">${icon(nav.trailing, 22)}</span>` : '';
    if (p === 'ios') {
      const back = nav.back ? `<span class="pv-nav-back">${icon('back', 22)}<span>${t(nav.back)}</span></span>` : '<span></span>';
      if (nav.large && !nav.back) {
        return `<div class="pv-nav pv-nav-ios large"><div class="pv-nav-bar">${back}${trailing}</div><div class="pv-nav-large">${t(nav.title)}</div></div>`;
      }
      return `<div class="pv-nav pv-nav-ios"><div class="pv-nav-bar">${back}<span class="pv-nav-title">${t(nav.title)}</span>${trailing || '<span></span>'}</div></div>`;
    }
    if (p === 'android') {
      const back = nav.back ? `<span class="pv-nav-back">${icon('arrowBack', 22)}</span>` : '';
      return `<div class="pv-nav pv-nav-android">${back}<span class="pv-nav-title">${t(nav.title)}</span><span class="pv-flex"></span>${nav.trailing ? `<span class="pv-nav-trailing">${icon(nav.trailing === 'more' ? 'moreVert' : nav.trailing, 22)}</span>` : ''}</div>`;
    }
    const back = nav.back ? `<span class="pv-nav-back">${icon('back', 22)}</span>` : '';
    return `<div class="pv-nav pv-nav-harmony">${back}<span class="pv-nav-title">${t(nav.title)}</span><span class="pv-flex"></span>${trailing}</div>`;
  }

  function tabBar(tabs, p) {
    if (!tabs) return '';
    const items = tabs.items
      .map(
        (item) =>
          `<span class="pv-tab${item.active ? ' active' : ''}"><span class="pv-tab-icon">${icon(item.icon, 22)}</span><span class="pv-tab-label">${t(item.s)}</span></span>`,
      )
      .join('');
    const extra = tabs.trailing ? `<span class="pv-tab pv-tab-extra"><span class="pv-tab-icon">${icon(tabs.trailing, 22)}</span><span class="pv-tab-label">${t(tabs.trailingLabel ?? '')}</span></span>` : '';
    return `<div class="pv-tabs pv-tabs-${p}">${items}${extra}</div>`;
  }

  const PLATFORMS = [
    { id: 'ios', name: 'iOS', toolkit: 'SwiftUI' },
    { id: 'android', name: 'Android', toolkit: 'Jetpack Compose · Material 3' },
    { id: 'harmony', name: 'HarmonyOS', toolkit: 'ArkUI' },
  ];

  function device(spec, p, options = {}) {
    const body = spec.body ?? [];
    const bg = spec.bg ?? (body.some((node) => node.t === 'list') ? 'grouped' : 'plain');
    const overlay = spec.overlay ? `<div class="pv-overlay">${children(spec.overlay, p)}</div>` : '';
    return `<div class="device device-${p}${options.dark ? ' dark' : ''}${options.compact ? ' compact' : ''}">
      <div class="device-screen bg-${bg}">
        <div class="device-status">${STATUS[p]}</div>
        ${navBar(spec.nav, p)}
        <div class="device-content${spec.center ? ' center' : ''}">${children(body, p)}</div>
        ${tabBar(spec.tabs, p)}
        ${overlay}
        <div class="device-home"></div>
      </div>
    </div>`;
  }

  window.RefractPreview = { device, PLATFORMS, icon };
})();
