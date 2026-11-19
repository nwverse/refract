// The curated component catalog.
//
// Every entry points at real golden fixtures under Fixtures/: the code panels show those files verbatim, and the
// "rejected forms" list shows the diagnostics the generator must produce. The `preview` spec is the only hand-written
// part: an illustrative drawing of the same screen on each platform, rendered by preview.js.
(function () {
  const C = [
    { id: 'text', en: 'Text & resources', zh: '文本与资源' },
    { id: 'layout', en: 'Layout', zh: '布局' },
    { id: 'controls', en: 'Controls', zh: '控件' },
    { id: 'lists', en: 'Lists & collections', zh: '列表与集合' },
    { id: 'state', en: 'State & control flow', zh: '状态与控制流' },
    { id: 'navigation', en: 'Navigation', zh: '导航' },
    { id: 'forms', en: 'Forms & input', zh: '表单与输入' },
    { id: 'rich', en: 'Rich content', zh: '富内容' },
    { id: 'design', en: 'Design system', zh: '设计系统' },
    { id: 'interop', en: 'Native interop', zh: '原生互操作' },
    { id: 'a11y', en: 'Accessibility', zh: '无障碍' },
  ];

  const entries = [
    // ---------------------------------------------------------------- Text & resources
    {
      id: 'text',
      category: 'text',
      title: 'Text',
      swiftui: 'Text("settings.title")',
      compose: 'Text(stringResource(R.string.…))',
      arkui: "Text($r('app.string.…'))",
      fixture: 'v0-hello-text',
      related: ['hello', 'localization/plain'],
      rejects: ['v0-reject-literal-text', 'v0-reject-missing-resource', 'localization/missing-android', 'localization/missing-harmony'],
      summary: {
        en: 'A string literal in Text is a localization key. It becomes an Android string resource and a HarmonyOS $r resource, both validated at build time.',
        zh: 'Text 里的字符串字面量是本地化 key，会变成 Android 的 string 资源和 HarmonyOS 的 $r 资源，构建时校验两端都已声明。',
      },
      notes: {
        en: ['Keys are lowercase dot-separated segments; `.` maps to `_` in both catalogs.', 'A missing key in either catalog is a build error, never a fallback string.'],
        zh: ['key 只能是小写点分段，`.` 在两端资源名里都换成 `_`。', '任意一端缺少该 key 都是构建错误，不会回退成原文。'],
      },
      preview: { center: true, body: [{ t: 'text', s: 'Hello, Refract' }] },
    },
    {
      id: 'text-verbatim',
      category: 'text',
      title: 'Verbatim text',
      swiftui: 'Text(verbatim: "Debug")',
      compose: 'Text(text = "Debug")',
      arkui: "Text('Debug')",
      fixture: 'v0-literal-text',
      rejects: ['interop-platform-text-localized-rejected'],
      summary: {
        en: 'Intentional, non-localized text. No resource lookup is generated.',
        zh: '明确不做本地化的字面文本，不生成任何资源查找。',
      },
      preview: { center: true, body: [{ t: 'text', s: 'Debug build' }] },
    },
    {
      id: 'text-formatted',
      category: 'text',
      title: 'Formatted text',
      swiftui: 'Text("settings.item.count\\(model.count)")',
      compose: 'stringResource(R.string.settings_item_count, count)',
      arkui: "$r('app.string.settings_item_count', count)",
      fixture: 'v0-formatted-text',
      related: ['localization/formatted'],
      summary: {
        en: 'Interpolation in a localized key becomes ordered, typed resource arguments (%1$d), checked against both catalogs.',
        zh: '本地化 key 里的插值会变成有序、带类型的资源参数（%1$d），并与两端资源目录做一致性校验。',
      },
      preview: { center: true, body: [{ t: 'text', s: '12 items' }] },
    },
    {
      id: 'text-styled',
      category: 'text',
      title: 'Typography & modifiers',
      swiftui: '.font / .foregroundStyle / .padding / .background / .cornerRadius',
      compose: 'TextStyle + Modifier chain',
      arkui: '.font() .fontColor() .padding() .backgroundColor() .borderRadius()',
      fixture: 'v0-styled-text',
      rejects: ['v0-reject-undefined-spacing', 'v0-reject-unsupported-modifier'],
      summary: {
        en: 'Design tokens for font, color, spacing and radius resolve to your own design system on each platform through refract.json. No RGB or size fallback.',
        zh: '字体、颜色、间距、圆角都通过 refract.json 解析成各端自己的设计系统 token，没有任何 RGB 或尺寸兜底值。',
      },
      preview: {
        body: [
          {
            t: 'vstack',
            pad: 16,
            children: [
              { t: 'card', children: [{ t: 'text', s: 'Appearance', style: 'title', tone: 'secondary' }] },
            ],
          },
        ],
      },
    },

    // ---------------------------------------------------------------- Layout
    {
      id: 'stacks',
      category: 'layout',
      title: 'VStack · HStack · ZStack · Spacer',
      swiftui: 'VStack / HStack / ZStack / Spacer',
      compose: 'Column / Row / Box / Spacer(weight)',
      arkui: 'Column / Row / Stack / Blank',
      fixture: 'v0-stack-layout',
      related: ['compose-typed-layout'],
      summary: {
        en: 'Stacks map one-to-one to native containers. Alignment is start/end (RTL-safe) and explicit spacing tokens are kept; omitted spacing keeps the toolkit default.',
        zh: '三种 Stack 一对一映射到原生容器。对齐用 start/end（支持 RTL），显式的间距 token 原样保留；不写间距时沿用工具包默认值。',
      },
      preview: {
        body: [
          {
            t: 'vstack',
            align: 'leading',
            gap: 8,
            pad: 16,
            children: [
              { t: 'text', s: 'Profile', style: 'headline' },
              { t: 'hstack', gap: 4, children: [{ t: 'text', s: 'Enabled' }, { t: 'spacer' }, { t: 'badge', s: 'Spacer →' }] },
              { t: 'zstack', align: 'topLeading', children: [{ t: 'image', h: 70, s: 'Background' }, { t: 'badge', s: 'Foreground' }] },
            ],
          },
        ],
      },
    },
    {
      id: 'scroll',
      category: 'layout',
      title: 'ScrollView',
      swiftui: 'ScrollView { … }',
      compose: 'Column(Modifier.verticalScroll(rememberScrollState()))',
      arkui: 'Scroll() { Column() { … } }',
      fixture: 'v0-scroll-content',
      related: ['compose-scroll'],
      rejects: ['compose-rejected-nested-scroll'],
      summary: {
        en: 'A vertical scroll container with remembered scroll state. Repeated collections belong in List, which is lazy.',
        zh: '纵向滚动容器，滚动状态会被 remember。重复数据请用懒加载的 List，而不是 ScrollView + ForEach。',
      },
      preview: {
        body: [
          {
            t: 'scroll',
            pad: 16,
            gap: 12,
            children: [
              { t: 'text', s: 'First', style: 'headline' },
              { t: 'text', s: 'Second', style: 'headline' },
              { t: 'text', s: 'Long-form content keeps scrolling…', tone: 'secondary' },
              { t: 'image', h: 90 },
              { t: 'image', h: 90 },
            ],
          },
        ],
      },
    },
    {
      id: 'layout-priority',
      category: 'layout',
      title: 'Layout priority & frames',
      swiftui: '.layoutPriority(1) · .frame(maxWidth: .infinity)',
      compose: 'Modifier.weight(1f) · fillMaxWidth()',
      arkui: '.layoutWeight(1) · .width("100%")',
      fixture: 'child-view-layout-priority',
      summary: {
        en: 'A bounded flexible-layout slice: one direct HStack child takes the remaining width while the native control keeps its size.',
        zh: '受限的弹性布局：HStack 的一个直接子项占满剩余宽度，原生控件保持自身尺寸。',
      },
      preview: {
        body: [
          {
            t: 'list',
            sections: [
              {
                rows: [
                  { t: 'hstack', children: [{ t: 'vstack', align: 'leading', children: [{ t: 'text', s: 'Wi-Fi assist' }, { t: 'text', s: 'Use cellular when Wi-Fi is poor', style: 'caption', tone: 'secondary' }] }, { t: 'spacer' }, { t: 'toggle', on: true, hideLabel: true }] },
                  { t: 'hstack', children: [{ t: 'vstack', align: 'leading', children: [{ t: 'text', s: 'Background refresh' }, { t: 'text', s: 'Update content in the background', style: 'caption', tone: 'secondary' }] }, { t: 'spacer' }, { t: 'toggle', on: false, hideLabel: true }] },
                ],
              },
            ],
          },
        ],
      },
    },
    {
      id: 'adaptive',
      category: 'layout',
      title: 'Adaptive width alternatives',
      swiftui: 'switch widthSizeClass { case .compact … case .expanded … }',
      compose: 'when (widthSizeClass) { … }',
      arkui: 'if / else on the host-measured width class',
      fixture: 'adaptive-window-size',
      rejects: ['adaptive-reject-branches', 'adaptive-reject-input', 'adaptive-reject-navigation', 'adaptive-reject-size-class'],
      summary: {
        en: 'Two declared layouts chosen by a width class the native host measures. Compact stacks vertically; expanded splits into columns.',
        zh: '声明两套布局，由原生宿主测量的宽度等级来选择：紧凑时纵向排列，宽屏时分成两栏。',
      },
      preview: {
        body: [
          {
            t: 'vstack',
            align: 'leading',
            gap: 10,
            pad: 16,
            children: [
              { t: 'text', s: 'Profile settings', style: 'headline' },
              { t: 'field', s: 'Display name' },
              { t: 'toggle', s: 'Notifications', on: true },
              { t: 'button', s: 'Save' },
            ],
          },
        ],
      },
    },

    // ---------------------------------------------------------------- Controls
    {
      id: 'button',
      category: 'controls',
      title: 'Button',
      swiftui: 'Button("settings.save") { model.save() }',
      compose: 'Button(onClick = { model.save() }) { Text(…) }',
      arkui: 'Button() { Text(…) }.onClick(…)',
      fixture: 'v0-button-action',
      related: ['state-counter'],
      summary: {
        en: 'The action is exactly one call into the model or local state, so it lowers to a direct onClick with no captured Swift code.',
        zh: '按钮动作只能是一次对 model 或本地状态的调用，因此直接生成 onClick，不会携带任意 Swift 代码。',
      },
      preview: { center: true, body: [{ t: 'button', s: 'Save' }] },
    },
    {
      id: 'toggle',
      category: 'controls',
      title: 'Toggle',
      swiftui: 'Toggle("settings.enabled", isOn: $isEnabled)',
      compose: 'Row { Text(…); Switch(checked, onCheckedChange) }',
      arkui: 'Row() { Text(…); Blank(); Toggle({ type: ToggleType.Switch }) }',
      fixture: 'v0-local-state',
      related: ['v0-binding-state', 'v0-item-toggle', 'v0-item-toggle-value'],
      summary: {
        en: 'A native switch beside its localized title. The binding becomes value + change callback; there is no two-way-binding runtime.',
        zh: '原生开关加本地化标题。绑定会拆成「值 + 变更回调」，不需要任何双向绑定运行时。',
      },
      preview: {
        body: [{ t: 'list', sections: [{ rows: [{ t: 'toggle', s: 'Enabled', on: true }, { t: 'toggle', s: 'Notifications', on: false }] }] }],
      },
    },
    {
      id: 'textfield',
      category: 'controls',
      title: 'TextField',
      swiftui: 'TextField("settings.display.name", text: $name)',
      compose: 'TextField(value, onValueChange, label)',
      arkui: 'TextInput({ placeholder, text }).onChange(…)',
      fixture: 'v0-text-input',
      summary: {
        en: 'A native text input with a localized label or placeholder; every edit flows through the declared state write.',
        zh: '原生文本输入框，带本地化 label 或 placeholder；每次编辑都经过声明的状态写入。',
      },
      preview: {
        body: [{ t: 'vstack', gap: 12, pad: 16, children: [{ t: 'field', s: 'Display name' }, { t: 'field', s: 'Display name', value: 'Ada Lovelace', focused: true }] }],
      },
    },
    {
      id: 'securefield',
      category: 'controls',
      title: 'SecureField',
      swiftui: 'SecureField("settings.password", text: $password)',
      compose: 'TextField(visualTransformation = PasswordVisualTransformation())',
      arkui: 'TextInput(…).type(InputType.Password)',
      fixture: 'v0-secure-input',
      rejects: ['v0-reject-secure-input-literal', 'v0-reject-secure-reveal-literal'],
      summary: {
        en: 'Native secure entry, obscured by default. `.secureReveal($flag)` opts into a typed reveal; secrets never appear in generated source.',
        zh: '原生密码输入，默认遮挡。`.secureReveal($flag)` 显式开启可切换显示；生成代码里不会出现密文字面量。',
      },
      preview: {
        body: [{ t: 'vstack', gap: 12, pad: 16, children: [{ t: 'field', s: 'Password', value: 'hunter22', secure: true }, { t: 'field', s: 'Access token', secure: true }] }],
      },
    },
    {
      id: 'label-image',
      category: 'controls',
      title: 'Label · Image · Divider',
      swiftui: 'Label("…", systemImage: "person") · Image(systemName:) · Divider()',
      compose: 'Row { Icon; Text } · Icon(Icons.Default.…) · HorizontalDivider()',
      arkui: "Row() { Image($r('app.media.…')); Text } · Divider()",
      fixture: 'v0-leaf-controls',
      rejects: ['compose-rejected-system-image', 'rejected-image', 'v0-reject-unsupported-view'],
      summary: {
        en: 'SF Symbol names map to a typed per-platform symbol table (Material icon on Android, media resource on HarmonyOS). Unmapped symbols are errors.',
        zh: 'SF Symbol 名称通过类型化的符号表映射到各端（Android 用 Material 图标，HarmonyOS 用 media 资源），未映射的符号直接报错。',
      },
      preview: {
        body: [
          {
            t: 'vstack',
            gap: 14,
            pad: 16,
            children: [
              { t: 'label', icon: 'person', s: 'Profile' },
              { t: 'icon', name: 'gear', size: 28 },
              { t: 'button', icon: 'check', s: 'Save' },
              { t: 'divider' },
            ],
          },
        ],
      },
    },
    {
      id: 'image-assets',
      category: 'controls',
      title: 'Typed image & font assets',
      swiftui: 'Image("app_logo", label: Text("…")) · .font(.custom(…))',
      compose: 'painterResource(R.drawable.…) · FontFamily(Font(R.font.…))',
      arkui: "Image($r('app.media.…')) · .fontFamily(…)",
      fixture: 'resource-typed-assets',
      related: ['compose-image'],
      rejects: ['resource-reject-missing-assets', 'pending-contract'],
      summary: {
        en: 'App-packaged images and fonts are checked against an explicit asset catalog, including dark and density variants.',
        zh: '应用自带的图片和字体会对照显式的资源目录校验，包括深色与多密度变体。',
      },
      preview: {
        body: [{ t: 'vstack', gap: 12, pad: 16, children: [{ t: 'image', h: 140, s: 'app_logo' }, { t: 'text', s: 'Custom font body text', styleAttr: 'font-family: Georgia, serif' }] }],
      },
    },

    // ---------------------------------------------------------------- Lists
    {
      id: 'list-section',
      category: 'lists',
      title: 'List & Section',
      swiftui: 'List { Section("…") { … } }',
      compose: 'LazyColumn { item(key, contentType) { … } }',
      arkui: 'List() { ListItemGroup({ header }) { ListItem() { … } } }',
      fixture: 'v0-static-list',
      rejects: ['list-reject-mixed-rows'],
      summary: {
        en: 'Static rows become lazy items with stable keys and content types derived from the source, never array indices.',
        zh: '静态行生成为懒加载 item，key 与 contentType 都从源码推导，绝不使用数组下标。',
      },
      preview: {
        body: [
          {
            t: 'list',
            sections: [
              { header: 'General', rows: [{ t: 'navrow', s: 'Profile' }, { t: 'navrow', s: 'Notifications' }] },
              { rows: [{ t: 'navrow', s: 'About' }] },
            ],
          },
        ],
      },
    },
    {
      id: 'foreach',
      category: 'lists',
      title: 'ForEach & identified lists',
      swiftui: 'List { ForEach(model.items) { item in … } }',
      compose: 'items(items, key = { it.id }, contentType = { … })',
      arkui: 'LazyForEach(dataSource, …, (item) => item.id)',
      fixture: 'list-foreach',
      related: ['list-foreach-explicit-id', 'v0-identified-list', 'v0-item-toggle'],
      rejects: [
        'list-reject-eager-foreach',
        'list-reject-foreach-identity',
        'list-reject-foreach-item-property',
        'list-reject-misplaced-foreach',
        'list-reject-nested-foreach',
        'v0-reject-implicit-identity',
        'v0-reject-list-identity',
      ],
      summary: {
        en: 'Dynamic rows require Identifiable items; the id becomes the native list key so Compose and ArkUI can reuse rows instead of rebuilding them.',
        zh: '动态行要求 Identifiable，id 直接作为原生列表 key，Compose 和 ArkUI 可以复用行而不是重建。',
      },
      preview: {
        body: [{ t: 'list', sections: [{ rows: [{ t: 'text', s: 'Wi-Fi' }, { t: 'text', s: 'Bluetooth' }, { t: 'text', s: 'Mobile data' }, { t: 'text', s: 'Hotspot' }] }] }],
      },
    },
    {
      id: 'projection',
      category: 'lists',
      title: 'Typed list projection',
      swiftui: 'model.items.filter { … }.sorted { … }.refractProjection(name:)',
      compose: 'remember(model.items.value, category) { filter … sortedWith … }',
      arkui: 'export function catalogItems(items, category) { filter … sort … }',
      fixture: 'list-typed-projection',
      rejects: ['list-reject-projection-sort'],
      summary: {
        en: 'A bounded filter + sort over model items, computed once per input change rather than on every recomposition.',
        zh: '对 model 数据做受限的过滤与排序，只在输入变化时重新计算，而不是每次重组都算。',
      },
      preview: {
        body: [{ t: 'list', sections: [{ rows: [{ t: 'navrow', s: 'The Left Hand of Darkness', detail: '#1' }, { t: 'navrow', s: 'Arrival', detail: '#2' }, { t: 'navrow', s: 'Kindred', detail: '#3' }] }] }],
      },
    },
    {
      id: 'paged-search',
      category: 'lists',
      title: 'Search, loading & paging',
      swiftui: 'TextField + if model.isLoading … List(model.items)',
      compose: 'TextField · if (…) · LazyColumn',
      arkui: 'TextInput · if (…) · List',
      fixture: 'list-paged-search',
      summary: {
        en: 'Loading, error, empty and paged states driven entirely by the model; the generated screen owns no network work.',
        zh: '加载中、出错、空结果与分页都由 model 驱动，生成的界面本身不做任何网络请求。',
      },
      preview: {
        body: [
          {
            t: 'vstack',
            gap: 8,
            pad: 12,
            children: [
              { t: 'search', s: 'Search results', value: 'swift' },
              { t: 'list', sections: [{ rows: [{ t: 'text', s: 'Swift concurrency' }, { t: 'text', s: 'SwiftUI layout' }, { t: 'text', s: 'Swift macros' }] }] },
              { t: 'button', s: 'Load more' },
            ],
          },
        ],
      },
    },
    {
      id: 'chat',
      category: 'lists',
      title: 'Message projection',
      swiftui: 'List(model.messages) { MessageRow(message:) }',
      compose: 'LazyColumn(items(key = { it.id }))',
      arkui: 'List() { ForEach(…, (m) => m.id) }',
      fixture: 'chat-message-projection',
      related: ['chat-message-cross-file'],
      rejects: ['chat-message-reject-revision'],
      summary: {
        en: 'Application-owned message snapshots with stable identity, so streaming updates only re-render the changed block.',
        zh: '由应用持有的消息快照，具备稳定标识，流式更新时只重绘变化的那一块。',
      },
      preview: {
        bg: 'plain',
        body: [
          {
            t: 'vstack',
            gap: 8,
            pad: 12,
            children: [
              { t: 'bubble', s: 'How do I adopt one screen?', me: true },
              { t: 'bubble', s: 'Generate it, then call it from your native navigation.' },
              { t: 'bubble', s: 'And roll back?', me: true },
              { t: 'bubble', s: 'Call the hand-written screen with the same arguments.' },
            ],
          },
        ],
      },
    },

    // ---------------------------------------------------------------- State
    {
      id: 'state',
      category: 'state',
      title: '@State',
      swiftui: '@State private var count = 0',
      compose: 'var count by remember { mutableStateOf(0) }',
      arkui: '@Local count: number = 0',
      fixture: 'state-counter',
      related: ['v0-local-state'],
      rejects: ['v0-reject-state-wrapper', 'v0-reject-body-mutation'],
      summary: {
        en: 'View-local state stays inside the generated component, using each toolkit’s own state primitive.',
        zh: '视图本地状态留在生成的组件内部，使用各工具包自己的状态原语。',
      },
      preview: { center: true, body: [{ t: 'vstack', gap: 12, children: [{ t: 'text', s: 'Count: 3', style: 'headline' }, { t: 'button', s: 'Increment' }] }] },
    },
    {
      id: 'binding',
      category: 'state',
      title: '@Binding',
      swiftui: '@Binding var isEnabled: Bool',
      compose: 'isEnabled: Boolean, onIsEnabledChange: (Boolean) -> Unit',
      arkui: '@Param isEnabled · @Event onIsEnabledChange',
      fixture: 'parent-binding',
      related: ['v0-binding-state'],
      rejects: ['v0-reject-binding-initializer', 'rejected-binding-initializer'],
      summary: {
        en: 'A parent-owned value becomes a value parameter plus a change callback: state hoisting, as a native engineer would write it.',
        zh: '父级持有的值会变成「值参数 + 变更回调」，也就是原生工程师手写时的状态提升写法。',
      },
      preview: { center: true, body: [{ t: 'vstack', gap: 12, children: [{ t: 'text', s: 'Enabled: true' }, { t: 'button', s: 'Disable' }] }] },
    },
    {
      id: 'model',
      category: 'state',
      title: 'Model protocols',
      swiftui: 'protocol SettingsModel: RefractModel { var title: String { get }; func save() }',
      compose: 'interface SettingsModel { val title: State<String>; fun save() }',
      arkui: 'export interface SettingsModel { title: string; save(): void }',
      fixture: 'v0-model-screen',
      related: ['model-interface'],
      rejects: ['rejected-model-associated-type', 'rejected-model-async', 'rejected-model-overload', 'rejected-model-property'],
      summary: {
        en: 'Data comes in through a protocol that becomes a Kotlin or ArkTS interface. Your existing view models implement it; nothing is wrapped or mirrored.',
        zh: '数据通过 protocol 传入，生成为 Kotlin / ArkTS 接口。现有 ViewModel 直接实现即可，不做包装或镜像。',
      },
      preview: { body: [{ t: 'list', sections: [{ rows: [{ t: 'text', s: 'Profile settings', style: 'headline' }, { t: 'button', s: 'Save' }] }] }] },
    },
    {
      id: 'conditional',
      category: 'state',
      title: 'if / else',
      swiftui: 'if model.isEnabled { … } else { … }',
      compose: 'if (model.isEnabled.value) { … } else { … }',
      arkui: 'if (this.model.isEnabled) { … } else { … }',
      fixture: 'control-if-else',
      related: ['v0-conditional-content', 'control-optional-binding', 'control-optional-modifier'],
      rejects: ['control-reject-if-let'],
      summary: {
        en: 'Conditional content is native conditional UI; branches are typed, and optional unwrapping uses a bounded form.',
        zh: '条件内容直接生成原生条件 UI；分支有类型约束，可选值解包只支持受限形式。',
      },
      preview: { center: true, body: [{ t: 'text', s: 'Enabled', style: 'headline' }] },
    },
    {
      id: 'switch',
      category: 'state',
      title: 'switch over enums',
      swiftui: 'switch tab { case .home: … case .settings: … }',
      compose: 'when (tab) { Tab.home -> …; Tab.settings -> … }',
      arkui: 'if (this.tab === Tab.home) { … } else if …',
      fixture: 'control-switch-enum',
      related: ['control-switch-modifier', 'control-switch-payload', 'cross-file-enum-switch'],
      rejects: ['control-reject-associated-value', 'control-reject-nonexhaustive'],
      summary: {
        en: 'Exhaustive enum switches become `when` in Kotlin and if-chains in ArkTS; the enum itself is generated for both.',
        zh: '穷尽的枚举 switch 在 Kotlin 里生成 `when`，在 ArkTS 里生成 if 链；枚举类型本身也会同时生成。',
      },
      preview: { center: true, body: [{ t: 'text', s: 'Home', style: 'headline' }] },
    },
    {
      id: 'child-views',
      category: 'state',
      title: 'Child views & multiple files',
      swiftui: 'struct Row: View { let item: Item } · several --input files',
      compose: '@Composable fun Row(item: Item)',
      arkui: '@ComponentV2 export struct Row',
      fixture: 'cross-file-child-view',
      related: ['child-view-foreach-content-type', 'cross-file-two-models'],
      rejects: ['child-view-reject-recursion', 'cross-file-reject-duplicate', 'cross-file-reject-recursion', 'rejected-view-declaration'],
      summary: {
        en: 'Child views keep their own native component boundary, so a row change recomposes only that row. Declarations may live in separate files.',
        zh: '子视图保留独立的原生组件边界，某一行变化只会重组这一行。声明可以分散在多个文件中。',
      },
      preview: { body: [{ t: 'list', sections: [{ rows: [{ t: 'navrow', s: 'Row component', detail: 'Alpha' }, { t: 'navrow', s: 'Row component', detail: 'Beta' }] }] }] },
    },

    // ---------------------------------------------------------------- Navigation
    {
      id: 'navigation',
      category: 'navigation',
      title: 'NavigationStack',
      swiftui: 'NavigationStack(path:) · NavigationLink(value:) · .navigationDestination',
      compose: 'onPathNavigate(Route) + NavigationScreenDestinations(route)',
      arkui: '@Event onPathNavigate + NavigationScreenDestinations',
      fixture: 'navigation-host',
      related: ['navigation-native-destination', 'navigation-deep-restoration'],
      rejects: ['navigation-reject-child-untyped', 'navigation-reject-dynamic', 'navigation-reject-missing', 'navigation-reject-native-mapping', 'navigation-reject-payload'],
      summary: {
        en: 'Typed routes in a Hashable enum. The native host keeps back handling, lifecycle and restoration; a destination can be hand-written native code.',
        zh: '路由是 Hashable 枚举，有类型约束。返回、生命周期和状态恢复都归原生宿主管理；目标页也可以是手写原生代码。',
      },
      preview: {
        nav: { title: 'Settings', large: true },
        body: [{ t: 'list', sections: [{ rows: [{ t: 'text', s: 'Profile settings' }, { t: 'navrow', s: 'Open details' }] }] }],
      },
    },
    {
      id: 'tabs',
      category: 'navigation',
      title: 'TabView & Menu',
      swiftui: 'TabView(selection:) · .tabItem · Menu { Button … }',
      compose: 'NavigationBar · NavigationBarItem · DropdownMenu',
      arkui: 'Tabs({ barPosition: BarPosition.End }) · TabContent · bindMenu',
      fixture: 'navigation-tabs-menu',
      rejects: ['navigation-tabs-reject-dynamic', 'navigation-tabs-reject-inputs'],
      summary: {
        en: 'A static set of typed tabs with a toolbar menu, lowered to each platform’s own bottom navigation and menu.',
        zh: '静态、带类型的标签页加工具栏菜单，分别生成为各平台自己的底部导航和菜单。',
      },
      preview: {
        nav: { title: 'Activity', trailing: 'more' },
        center: true,
        body: [{ t: 'text', s: 'Recent activity', tone: 'secondary' }],
        tabs: { items: [{ icon: 'gear', s: 'Overview' }, { icon: 'person', s: 'Activity', active: true }] },
        overlay: [{ t: 'menu', items: ['Refresh', 'Reset'] }],
      },
    },

    // ---------------------------------------------------------------- Forms
    {
      id: 'form',
      category: 'forms',
      title: 'Form validation & submission',
      swiftui: 'refractForm { Field(…, rules:) } · form.submit(model.submit)',
      compose: 'Remembered field state, validation, model submit',
      arkui: '@Local field state, validation, model submit',
      fixture: 'form-validation',
      rejects: ['form-reject-presence-type', 'form-reject-submit-binding', 'form-reject-unknown-rule'],
      summary: {
        en: 'Declared fields and rules (nonEmpty, equals) are validated before an async model submit; submitting, error and retry states come from the model.',
        zh: '声明字段和规则（nonEmpty、equals），校验通过后才调用异步 submit；提交中、错误和重试状态都来自 model。',
      },
      preview: {
        body: [
          {
            t: 'list',
            sections: [
              { rows: [{ t: 'field', s: 'Email', value: 'me@example.com' }, { t: 'field', s: 'Password', value: 'secret', secure: true }, { t: 'field', s: 'Confirm password', value: 'secrex', secure: true }] },
              { rows: [{ t: 'error', s: 'Passwords do not match' }, { t: 'button', s: 'Submit' }] },
            ],
          },
        ],
      },
    },
    {
      id: 'text-input-host',
      category: 'forms',
      title: 'Native text input host',
      swiftui: 'struct Host: RefractTextInputHost { @Binding var draft … }',
      compose: 'App-owned native input composable',
      arkui: 'App-owned native TextInput component',
      fixture: 'interop-text-input-host',
      summary: {
        en: 'Focus, keyboard, IME composition and committed drafts stay owned by native code; the screen only sees committed values.',
        zh: '焦点、键盘、输入法组字和草稿提交都由原生代码掌握，生成的界面只拿到已提交的值。',
      },
      preview: {
        bg: 'plain',
        body: [{ t: 'vstack', gap: 8, pad: 12, children: [{ t: 'spacer' }, { t: 'native', tag: 'native input', icon: 'send', s: 'Message' }] }],
      },
    },

    // ---------------------------------------------------------------- Rich content
    {
      id: 'markdown',
      category: 'rich',
      title: 'Typed Markdown',
      swiftui: 'refractMarkdown(version: 1, blocks: [.paragraph(…), .codeBlock(…)])',
      compose: 'AnnotatedString spans + code block',
      arkui: 'Text() { Span() … } + code block',
      fixture: 'markdown-conversation',
      rejects: ['markdown-reject-html', 'markdown-reject-link', 'markdown-reject-runtime'],
      summary: {
        en: 'A literal, versioned rich-text AST (emphasis, inline code, HTTPS links, code blocks) — not runtime Markdown or HTML parsing.',
        zh: '字面、带版本的富文本 AST（强调、行内代码、HTTPS 链接、代码块），不是运行时 Markdown 或 HTML 解析。',
      },
      preview: {
        bg: 'plain',
        body: [
          {
            t: 'vstack',
            align: 'leading',
            gap: 10,
            pad: 16,
            children: [
              { t: 'rich', parts: ['Here is a ', { b: 'bounded answer' }, { i: ' with an example: ' }, { code: 'let answer = 42' }, { link: ' Read the documentation' }] },
              { t: 'codeblock', s: 'func answer() -> Int {\n    return 42\n}' },
            ],
          },
        ],
      },
    },
    {
      id: 'selection',
      category: 'rich',
      title: 'Selection & link context',
      swiftui: '.refractNativeModifier(.textSelection(…)) · link activation',
      compose: 'App-owned NativeSelectionMessage(range, link, context)',
      arkui: 'App-owned native selection component',
      fixture: 'selection-link-context',
      rejects: ['selection-link-context-reject'],
      summary: {
        en: 'Bounded literal selection ranges and link activation, with context snapshots owned by the model.',
        zh: '受限的字面选区与链接激活，上下文快照归 model 持有。',
      },
      preview: {
        bg: 'plain',
        body: [{ t: 'vstack', align: 'leading', pad: 16, gap: 6, children: [{ t: 'selection', before: 'Refract generates ', selected: 'native code', after: ' at build time.', actions: ['Copy', 'Select all', 'Share'] }] }],
      },
    },
    {
      id: 'dragdrop',
      category: 'rich',
      title: 'Drag & drop payloads',
      swiftui: '.refractNativeModifier(.dragPayload(kind:value:)) · .dropTarget',
      compose: 'Modifier.dragAndDropSource / Target',
      arkui: '.onDragStart / .onDrop',
      fixture: 'selection-dragdrop',
      rejects: ['selection-reject-uri-payload'],
      summary: {
        en: 'A typed text payload contract between a drag source and a drop target; URIs and arbitrary data are rejected.',
        zh: '拖拽源与放置目标之间的类型化文本负载约定；URI 和任意数据会被拒绝。',
      },
      preview: {
        body: [
          {
            t: 'vstack',
            gap: 14,
            pad: 16,
            children: [
              { t: 'field', s: 'Display name' },
              { t: 'card', children: [{ t: 'label', icon: 'move', s: 'Drag me' }] },
              { t: 'native', tag: 'drop target', s: 'Drop here' },
            ],
          },
        ],
      },
    },

    // ---------------------------------------------------------------- Design system
    {
      id: 'design-system',
      category: 'design',
      title: 'Your design-system components',
      swiftui: 'StatusBadge(title: "…")',
      compose: 'PrimaryBadge(title = stringResource(…))  // your component',
      arkui: "PrimaryBadge({ title: $r('app.string.…') })  // your component",
      fixture: 'v0-design-system',
      related: ['mapping/brand-a', 'mapping/brand-b', 'mapping/model-scalars'],
      rejects: ['mapping/missing-component', 'mapping/missing-resource', 'mapping/missing-token'],
      summary: {
        en: 'refract.json maps a source component to your own Compose and ArkUI components, with typed parameters checked at generation time.',
        zh: 'refract.json 把源码组件映射到你自己的 Compose 和 ArkUI 组件，参数类型在生成时校验。',
      },
      preview: { center: true, body: [{ t: 'badge', s: 'Online' }] },
    },
    {
      id: 'interaction-states',
      category: 'design',
      title: 'Interaction-state colors',
      swiftui: 'refractInteractionColor(token, enabled:, pressed:, focused:)',
      compose: 'AppInteractionColors resolved from your theme',
      arkui: 'Interaction color resolved from your theme',
      fixture: 'theme-interaction-states',
      rejects: ['theme-reject-missing-state'],
      summary: {
        en: 'A color token with enabled, pressed and focused variants, resolved from your native theme (light and dark).',
        zh: '带 enabled、pressed、focused 变体的颜色 token，从原生主题（含深色）中解析。',
      },
      preview: {
        body: [{ t: 'vstack', gap: 10, pad: 16, children: [{ t: 'card', children: [{ t: 'text', s: 'Appearance and notifications' }] }] }],
      },
    },

    // ---------------------------------------------------------------- Interop
    {
      id: 'native-view',
      category: 'interop',
      title: 'Embed a native view',
      swiftui: 'struct RoutePreview: RefractNativeView { let zoom: Double … }',
      compose: 'RoutePreview(zoom = 12.0, showsTraffic = true)  // your Composable',
      arkui: 'RoutePreview({ zoom: 12.0, showsTraffic: true })  // your component',
      fixture: 'interop-native-component',
      related: ['v0-native-component', 'interop-native-callers'],
      rejects: ['interop-native-mismatch', 'interop-native-missing', 'interop-native-undeclared', 'v0-reject-native-missing', 'v0-reject-native-type'],
      summary: {
        en: 'Declare a native view in Swift: its SwiftUI body is the iOS implementation, and refract.json names the hand-written Compose and ArkUI ones. Direct calls, no registry.',
        zh: '在 Swift 里声明原生视图：它的 SwiftUI body 就是 iOS 实现，refract.json 指向手写的 Compose 和 ArkUI 实现。直接调用，没有注册表。',
      },
      preview: {
        body: [
          {
            t: 'vstack',
            gap: 10,
            pad: 16,
            align: 'leading',
            children: [
              { t: 'text', s: 'Route', style: 'headline' },
              { t: 'native', icon: 'globe', s: 'RoutePreview', sub: { ios: 'SwiftUI body', android: 'Hand-written Composable', harmony: 'Hand-written ArkUI component' } },
            ],
          },
        ],
      },
    },
    {
      id: 'platform-value',
      category: 'interop',
      title: 'Per-platform values & views',
      swiftui: 'refractValue(ios:android:harmonyOS:) · refractView(ios:android:harmonyOS:)',
      compose: 'Only the Android branch is emitted',
      arkui: 'Only the HarmonyOS branch is emitted',
      fixture: 'interop-platform-value',
      related: ['interop-platform-view'],
      rejects: ['interop-platform-value-incomplete', 'interop-reject-conditional-compilation', 'v0-reject-platform-if'],
      summary: {
        en: 'Deliberate platform differences are declared in the source. Each backend emits only its own branch — no runtime dispatch, no AnyView.',
        zh: '有意的平台差异直接写在源码里，每个后端只生成自己那一支，没有运行时分发，也没有 AnyView。',
      },
      preview: {
        center: true,
        body: [
          {
            t: 'vstack',
            gap: 8,
            children: [
              { t: 'text', s: 'Spacing', tone: 'secondary' },
              { t: 'platform', ios: { t: 'badge', s: 'iOS' }, android: { t: 'badge', s: 'Android' }, harmony: { t: 'badge', s: 'HarmonyOS' } },
            ],
          },
        ],
      },
    },
    {
      id: 'remote-image',
      category: 'interop',
      title: 'Remote images',
      swiftui: 'RemoteImage(url:, placeholder:, failure:, loader:)',
      compose: 'Your image loader composable',
      arkui: 'Your image loader component',
      fixture: 'interop-remote-image',
      rejects: ['interop-remote-image-reject'],
      summary: {
        en: 'HTTPS-only image sources with placeholder and failure assets. The app keeps its own image loader and cache.',
        zh: '仅限 HTTPS 的图片源，带占位与失败图；图片加载器和缓存仍归应用自己。',
      },
      preview: { body: [{ t: 'vstack', gap: 10, pad: 16, children: [{ t: 'image', h: 180, icon: 'person', s: 'Profile photo' }] }] },
    },
    {
      id: 'link-handoff',
      category: 'interop',
      title: 'Link handoff',
      swiftui: 'RefractLinkDestination.https(host:path:) · RefractLinkPolicy',
      compose: 'Native confirmation + app-owned routing',
      arkui: 'Native confirmation + app-owned routing',
      fixture: 'interop-link-handoff',
      rejects: ['interop-link-handoff-reject'],
      summary: {
        en: 'Bounded HTTPS and deep-link destinations behind an allow-list, with native confirmation and cancellation.',
        zh: '受白名单约束的 HTTPS 与 deep link 目标，带原生确认与取消。',
      },
      preview: {
        center: true,
        body: [{ t: 'vstack', gap: 12, children: [{ t: 'button', s: 'Open help' }, { t: 'button', s: 'Open article' }] }],
        overlay: [{ t: 'sheet', children: [{ t: 'text', s: 'Open https://docs.example.test?', style: 'headline' }, { t: 'button', s: 'Open' }, { t: 'text', s: 'Cancel', tone: 'accent' }] }],
      },
    },
    {
      id: 'document-preview',
      category: 'interop',
      title: 'Document preview',
      swiftui: 'NativeDocumentPreview(uri:displayName:mimeType:…)',
      compose: 'App-owned native previewer',
      arkui: 'App-owned native previewer',
      fixture: 'interop-document-preview',
      rejects: ['interop-document-preview-reject'],
      summary: {
        en: 'Typed loading, ready, missing, unsupported, cancelled and closed states; the native previewer owns the file.',
        zh: '有类型的加载中、就绪、缺失、不支持、已取消、已关闭状态；文件本身由原生预览器管理。',
      },
      preview: {
        nav: { title: 'Report.pdf', back: 'Back' },
        body: [{ t: 'vstack', gap: 10, pad: 16, children: [{ t: 'native', icon: 'doc', s: 'Native document previewer' }, { t: 'button', s: 'Close document' }] }],
      },
    },
    {
      id: 'native-hosts',
      category: 'interop',
      title: 'Lifecycle, notifications & background work',
      swiftui: 'RefractLifecycleHost · .refractOnAppear · @RefractNativeValue',
      compose: 'DisposableEffect with the native LifecycleHost',
      arkui: 'aboutToAppear / aboutToDisappear',
      fixture: 'interop-native-lifecycle',
      related: ['interop-native-notification', 'interop-native-background-work', 'interop-native-state-transition', 'interop-native-measurement', 'interop-native-animation'],
      summary: {
        en: 'Foreground/background phases, notifications, deferred work, measurement and animation stay in native hosts; the screen receives typed values.',
        zh: '前后台切换、通知、延后任务、测量与动画都留在原生宿主里，界面只接收类型化的值。',
      },
      preview: { center: true, body: [{ t: 'vstack', gap: 8, children: [{ t: 'badge', s: 'foreground' }, { t: 'text', s: 'Synthetic foreground' }] }] },
    },

    // ---------------------------------------------------------------- Accessibility
    {
      id: 'a11y-actions',
      category: 'a11y',
      title: 'Accessibility actions & traversal',
      swiftui: '.accessibilityLabel / Hint / Value / Action · .accessibilityTraversal',
      compose: 'Modifier.semantics { … customActions; traversalIndex }',
      arkui: '.accessibilityText / Description / CustomActions / NextFocusId',
      fixture: 'accessibility-actions-traversal',
      summary: {
        en: 'Localized labels, hints, values, custom actions and a declared reading order, lowered to each platform’s native accessibility API.',
        zh: '本地化的标签、提示、值、自定义动作和声明的朗读顺序，分别生成到各平台原生的无障碍 API。',
      },
      preview: {
        body: [
          {
            t: 'vstack',
            align: 'leading',
            gap: 10,
            pad: 16,
            children: [
              { t: 'text', s: 'Synchronization', style: 'headline' },
              { t: 'button', s: 'Sync now' },
              { t: 'button', s: 'Show synchronization details' },
              { t: 'badge', s: '“Synchronize settings, button. Updates settings from the server.”' },
            ],
          },
        ],
      },
    },
    {
      id: 'dynamic-type',
      category: 'a11y',
      title: 'Dynamic type & native semantics',
      swiftui: 'Text without fixed sizes · native Toggle / TextField / Button',
      compose: 'sp-based typography · real Switch / TextField / Button',
      arkui: 'fp-based fonts · real Toggle / TextInput / Button',
      fixture: 'accessibility-dynamic-type',
      summary: {
        en: 'Text scales with the user’s font size and controls keep their native role, value and label. No fixed pixel sizes are invented.',
        zh: '文字随用户字号缩放，控件保留原生的角色、值和标签，不会凭空写死像素尺寸。',
      },
      preview: {
        body: [{ t: 'vstack', align: 'leading', gap: 10, pad: 16, children: [{ t: 'text', s: 'Large text', style: 'title' }, { t: 'toggle', s: 'Notifications', on: true }, { t: 'field', s: 'Display name' }, { t: 'button', s: 'Save' }] }],
      },
    },
  ];

  // The hero example on the overview page: the full settings screen used by the example apps.
  const showcase = {
    fixture: 'v0-settings-screen',
    preview: {
      nav: { title: 'Settings', large: true },
      body: [
        {
          t: 'list',
          sections: [
            { header: 'Profile', rows: [{ t: 'text', s: 'Profile settings' }, { t: 'field', s: 'Display name' }] },
            { header: 'Preferences', rows: [{ t: 'toggle', s: 'Notifications', on: true }] },
            { rows: [{ t: 'button', s: 'Save' }] },
          ],
        },
      ],
    },
  };

  window.RefractCatalog = { categories: C, entries, showcase };
})();
