// A small, dependency-free syntax highlighter for the languages the gallery shows: Swift, Kotlin, ArkTS, JSON, XML
// and Refract diagnostics. It only colors tokens; it never reformats source text.
(function () {
  const KEYWORDS = {
    swift: 'import struct enum protocol let var func some return if else switch case default for in true false nil self Self private public static where guard get set inout throws async await try init extension class final',
    kotlin: 'package import public private internal fun val var by return if else when for in is as true false null object class interface data enum sealed override suspend remember it this const',
    ets: 'import export from struct interface class enum let const function return if else for of in new true false null undefined this private public static readonly type void boolean string number build',
  };
  const sets = Object.fromEntries(Object.entries(KEYWORDS).map(([lang, words]) => [lang, new Set(words.split(' '))]));

  function escape(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function span(cls, text) {
    return `<span class="tk-${cls}">${escape(text)}</span>`;
  }

  function code(source, lang) {
    const keywords = sets[lang] ?? new Set();
    const pattern =
      /(\/\/[^\n]*|\/\*[\s\S]*?\*\/)|("(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\]|\\.)*`)|(@[A-Za-z_][\w]*)|(\$\$?[A-Za-z_][\w.]*|\$r)|(\b\d+(?:\.\d+)?(?:f|dp|sp|vp|fp)?\b)|([A-Za-z_][\w]*)/g;
    let out = '';
    let last = 0;
    let match;
    while ((match = pattern.exec(source))) {
      out += escape(source.slice(last, match.index));
      last = pattern.lastIndex;
      const [text, comment, string, annotation, binding, number, word] = match;
      if (comment) out += span('comment', text);
      else if (string) out += span('string', text);
      else if (annotation) out += span('attr', text);
      else if (binding) out += span('binding', text);
      else if (number) out += span('number', text);
      else if (word) {
        const next = source.slice(last).match(/^\s*([({<])/);
        if (keywords.has(word)) out += span('keyword', text);
        else if (/^[A-Z]/.test(word)) out += span(next && next[1] !== '<' ? 'call-type' : 'type', text);
        else if (next && next[1] === '(') out += span('call', text);
        else if (source[match.index - 1] === '.') out += span('member', text);
        else out += escape(text);
      }
    }
    return out + escape(source.slice(last));
  }

  function json(source) {
    return source.replace(
      /("(?:[^"\\]|\\.)*")(\s*:)?|\b(true|false|null)\b|(-?\b\d+(?:\.\d+)?\b)|([^"\w-]+|[\w-]+)/g,
      (all, string, colon, literal, number) => {
        if (string) return colon ? span('member', string) + escape(colon) : span('string', string);
        if (literal) return span('keyword', literal);
        if (number) return span('number', number);
        return escape(all);
      },
    );
  }

  function xml(source) {
    return escape(source)
      .replace(/(&lt;\/?)([\w:.-]+)/g, '$1<span class="tk-type">$2</span>')
      .replace(/([\w:-]+)=(&quot;|")([^"]*)"/g, '<span class="tk-member">$1</span>=<span class="tk-string">"$3"</span>');
  }

  function diagnostics(source) {
    return source
      .split('\n')
      .map((line) => {
        const match = line.match(/^(.+?:\d+:\d+): (error|warning) (\[[^\]]+\]): (.*?)( Suggestion: .*)?$/);
        if (!match) return escape(line);
        const [, where, severity, code, message, suggestion] = match;
        return (
          span('comment', where) +
          ': ' +
          span('error', severity) +
          ' ' +
          span('attr', code) +
          ': ' +
          escape(message) +
          (suggestion ? `<span class="tk-suggestion">${escape(suggestion)}</span>` : '')
        );
      })
      .join('\n');
  }

  function languageOf(name) {
    if (name.endsWith('.swift')) return 'swift';
    if (name.endsWith('.kt')) return 'kotlin';
    if (name.endsWith('.ets') || name.endsWith('.ts')) return 'ets';
    if (name.endsWith('.json') || name.endsWith('.json5')) return 'json';
    if (name.endsWith('.xml')) return 'xml';
    if (name.endsWith('.diagnostics')) return 'diagnostics';
    if (name.endsWith('.sh')) return 'shell';
    return 'text';
  }

  function highlight(source, lang) {
    switch (lang) {
      case 'swift':
      case 'kotlin':
      case 'ets':
        return code(source, lang);
      case 'json':
        return json(source);
      case 'xml':
        return xml(source);
      case 'diagnostics':
        return diagnostics(source);
      case 'shell':
        return source
          .split('\n')
          .map((line) => (line.trim().startsWith('#') ? span('comment', line) : escape(line)))
          .join('\n');
      default:
        return escape(source);
    }
  }

  window.RefractHighlight = { highlight, languageOf, escape };
})();
