/* 大肥鱼提示词工坊 · 面板逻辑 */

const post = (payload) => {
  try {
    window.webkit.messageHandlers.fish.postMessage(payload);
  } catch (err) {
    console.warn('bridge unavailable', err);
  }
};

const $ = (id) => document.getElementById(id);
const els = {
  card: $('card'),
  input: $('input'),
  btnGo: $('btnGo'),
  btnCopy: $('btnCopy'),
  btnClear: $('btnClear'),
  btnHistory: $('btnHistory'),
  btnHide: $('btnHide'),
  btnPin: $('btnPin'),
  btnSettings: $('btnSettings'),
  output: $('output'),
  outMeta: $('outMeta'),
  refine: $('refine'),
  chips: $('chips'),
  bubble: $('bubble'),
  bubbleText: $('bubbleText'),
  statusText: $('statusText'),
  dot: $('dot'),
  modelText: $('modelText'),
  settingsSheet: $('settingsSheet'),
  historySheet: $('historySheet'),
  historyList: $('historyList'),
  keyInput: $('keyInput'),
  btnSaveKey: $('btnSaveKey'),
  btnOpenFolder: $('btnOpenFolder'),
  toast: $('toast'),
  ideas: $('ideas'),
  opacityRange: $('opacityRange'),
  opacityValue: $('opacityValue'),
  sizeW: $('sizeW'),
  sizeH: $('sizeH')
};

const state = {
  preset: 'general',
  busy: false,
  lastPrompt: '',
  lastUserText: '',
  tipIndex: 0,
  appearance: { opacity: 80, width: 470, height: 726 }
};

const APPEARANCE_LIMITS = { minW: 380, maxW: 1000, minH: 480, maxH: 1000 };
const clampNum = (value, lo, hi) => Math.min(hi, Math.max(lo, Math.round(Number(value) || 0)));

// 透明度越低，越需要一层白色底板兜底，保证正文 WCAG AA 4.5:1。
// 分段线性：黑色桌面下的实测包络线，含安全余量。
const SCRIM_KNOTS = [[0, 0.62], [0.2, 0.53], [0.4, 0.36], [0.6, 0.14], [0.8, 0]];
function scrimFor(opacityPct) {
  const o = opacityPct / 100;
  if (o >= 0.8) return 0;
  for (let i = 1; i < SCRIM_KNOTS.length; i++) {
    const [o1, s1] = SCRIM_KNOTS[i];
    if (o <= o1) {
      const [o0, s0] = SCRIM_KNOTS[i - 1];
      return s0 + (s1 - s0) * ((o - o0) / (o1 - o0));
    }
  }
  return 0;
}

function applyAppearance(next = {}, notify = false) {
  const opacity = clampNum(next.opacity ?? state.appearance.opacity, 0, 100);
  const width = clampNum(next.width ?? state.appearance.width, APPEARANCE_LIMITS.minW, APPEARANCE_LIMITS.maxW);
  const height = clampNum(next.height ?? state.appearance.height, APPEARANCE_LIMITS.minH, APPEARANCE_LIMITS.maxH);
  state.appearance = { opacity, width, height };

  document.documentElement.classList.toggle('pw-low-alpha', opacity < 55);
  const root = document.documentElement.style;
  root.setProperty('--pw-card-bg-opacity', String(opacity / 100));
  root.setProperty('--pw-card-scrim', scrimFor(opacity).toFixed(3));
  root.setProperty('--pw-card-width', `${width - 32}px`);   // .stage 左右各 16px
  root.setProperty('--pw-card-height', `${height - 32}px`);

  if (els.opacityRange) els.opacityRange.value = String(opacity);
  if (els.opacityValue) els.opacityValue.textContent = `${opacity}%`;
  if (els.sizeW) els.sizeW.value = String(width);
  if (els.sizeH) els.sizeH.value = String(height);
  if (els.opacityRange) els.opacityRange.style.setProperty('--fill', `${opacity}%`);

  if (notify) {
    clearTimeout(applyAppearance.timer);
    applyAppearance.timer = setTimeout(() => {
      post({ cmd: 'appearance', opacity, width, height });
    }, 90);
  }
}

// ---------- 渲染 ----------

function escapeHTML(text) {
  return text.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}

function inline(text) {
  return escapeHTML(text)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
}

function renderOutline(text) {
  // 把「# 标题 / ## 标题 / - 列表 / 普通段落」渲染成结构清晰的 HTML（不是完整 markdown）
  return text.split('\n').map((raw) => {
    const line = raw.trimEnd();
    if (!line.trim()) return '';
    if (/^#\s+/.test(line)) {
      return `<div class="h1">${inline(line.replace(/^#\s+/, ''))}</div>`;
    }
    if (/^##\s+/.test(line)) {
      return `<div class="h2">${inline(line.replace(/^##\s+/, ''))}</div>`;
    }
    if (/^\s*[-*]\s+/.test(line)) {
      return `<div class="li">${inline(line.replace(/^\s*[-*]\s+/, ''))}</div>`;
    }
    if (/^\s*\d+\.\s+/.test(line)) {
      return `<div class="li">${inline(line.replace(/^\s*\d+\.\s+/, ''))}</div>`;
    }
    return `<div class="p">${inline(line)}</div>`;
  }).join('');
}

function showEmpty() {
  els.output.innerHTML = `
    <div class="empty" id="emptyState">
      <img class="empty-pet" src="../pet/fatfish-idle-0.webp" alt="大肥鱼">
      <p class="empty-title">还没有提示词</p>
      <p class="empty-sub">说两句大白话，我把它写成结构完整、<br>能直接粘贴的 agent 提示词。</p>
      <div class="ideas" id="ideas">
        <button class="idea">给 Claude Code 写个「只改这一处」的重构提示词</button>
        <button class="idea">把论文讨论段限制在 400 字，别夸大结论</button>
        <button class="idea">做一个介绍手冲咖啡器具的杂志风静态网站</button>
      </div>
    </div>`;
  bindIdeas();
}

function bindIdeas() {
  const box = $('ideas');
  if (!box) return;
  box.addEventListener('click', (event) => {
    const btn = event.target.closest('.idea');
    if (!btn) return;
    els.input.value = btn.textContent.trim();
    els.input.focus();
  });
}

function setBusy(on) {
  state.busy = on;
  els.card.classList.toggle('busy', on);
  els.btnGo.disabled = on;
  els.btnGo.innerHTML = on
    ? '<span class="label">停止</span>'
    : '<span class="label">生成提示词</span>';
}

function setOutputMeta(text) {
  els.outMeta.textContent = text || '';
}

function toast(text) {
  els.toast.textContent = text;
  els.toast.hidden = false;
  requestAnimationFrame(() => els.toast.classList.add('show'));
  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => {
    els.toast.classList.remove('show');
    setTimeout(() => { els.toast.hidden = true; }, 220);
  }, 1800);
}

// ---------- 生成 ----------

function systemPrompt() {
  const preset = PRESETS[state.preset] || PRESETS.general;
  return SYSTEM_BASE + preset.extra;
}

function startGenerate(userText, mode) {
  if (state.busy) return;
  const text = (userText || '').trim();
  if (!text) {
    els.input.focus();
    els.bubble.classList.add('pop');
    toast('先说说你想写什么');
    return;
  }
  if (els.settingsSheet.hidden === false) hideSheet(els.settingsSheet);

  state.lastUserText = text;
  setBusy(true);
  showStreaming();
  post({
    cmd: 'generate',
    messages: [
      { role: 'system', content: systemPrompt() },
      { role: 'user', content: mode === 'refine' ? text : `请把下面这段需求写成结构化提示词：\n\n${text}` }
    ]
  });
}

function showStreaming() {
  els.output.innerHTML = '<div class="md"><div class="p"><span class="cursor"></span></div></div>';
  els.refine.classList.remove('show');
  setOutputMeta('生成中…');
}

// ---------- 渲染提示词 ----------

function presentPrompt(text) {
  state.lastPrompt = text;
  els.output.innerHTML = `<div class="md">${renderOutline(text)}</div>`;
  els.output.scrollTop = 0;
  els.refine.classList.add('show');
  const chars = text.length;
  setOutputMeta(`${chars} 字 · 结构 ${(text.match(/^##\s+/gm) || []).length} 节`);
  saveHistory(text, state.lastUserText);
}

// ---------- 历史 ----------

function historyKey() { return 'fatfish.history.v2'; }

function loadHistory() {
  try {
    const raw = JSON.parse(localStorage.getItem(historyKey()) || '[]');
    return Array.isArray(raw) ? raw : [];
  } catch { return []; }
}

function saveHistory(prompt, source) {
  const list = loadHistory();
  list.unshift({
    id: Date.now(),
    prompt,
    source: (source || '').slice(0, 80),
    at: new Date().toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }),
    preset: state.preset
  });
  try {
    localStorage.setItem(historyKey(), JSON.stringify(list.slice(0, 20)));
  } catch { /* 容量满时忽略 */ }
}

function renderHistory() {
  const list = loadHistory();
  if (!list.length) {
    els.historyList.innerHTML = '<p class="history-empty">还没有记录，写一条试试～</p>';
    return;
  }
  els.historyList.innerHTML = list.map((item) => `
    <div class="history-item" data-id="${item.id}">
      <div class="hi-top"><span>${escapeHTML(item.at || '')}</span><span>${escapeHTML(PRESETS[item.preset]?.label || '')}</span></div>
      <div class="hi-text">${escapeHTML(item.source || item.prompt.slice(0, 60))}</div>
    </div>`).join('');
  els.historyList.querySelectorAll('.history-item').forEach((node) => {
    node.addEventListener('click', () => {
      const item = list.find((entry) => String(entry.id) === node.dataset.id);
      if (!item) return;
      presentPrompt(item.prompt);
      hideSheet(els.historySheet);
      toast('已载入，可继续精修');
    });
  });
}

// ---------- 浮层 ----------

function showSheet(sheet) { sheet.hidden = false; }
function hideSheet(sheet) { sheet.hidden = true; }

document.querySelectorAll('[data-close]').forEach((btn) => {
  btn.addEventListener('click', () => hideSheet($(btn.dataset.close)));
});

// ---------- 事件 ----------

els.chips.addEventListener('click', (event) => {
  const chip = event.target.closest('.chip');
  if (!chip) return;
  els.chips.querySelectorAll('.chip').forEach((node) => node.classList.remove('active'));
  chip.classList.add('active');
  state.preset = chip.dataset.preset;
  const preset = PRESETS[state.preset];
  if (preset) els.input.placeholder = preset.placeholder;
});

els.btnGo.addEventListener('click', () => {
  if (state.busy) {
    post({ cmd: 'cancel' });
    return;
  }
  startGenerate(els.input.value, 'new');
});

els.btnCopy.addEventListener('click', () => {
  if (!state.lastPrompt) { toast('还没有内容可复制'); return; }
  post({ cmd: 'copy', text: state.lastPrompt });
});

els.btnClear.addEventListener('click', () => {
  state.lastPrompt = '';
  setOutputMeta('');
  els.refine.classList.remove('show');
  showEmpty();
});

els.btnHistory.addEventListener('click', () => {
  renderHistory();
  showSheet(els.historySheet);
});

els.btnSettings.addEventListener('click', () => {
  els.keyInput.value = '';
  showSheet(els.settingsSheet);
});

els.btnSaveKey.addEventListener('click', () => {
  post({ cmd: 'saveKey', key: els.keyInput.value.trim() });
  hideSheet(els.settingsSheet);
  toast('已保存');
});

els.btnOpenFolder.addEventListener('click', () => post({ cmd: 'openProject' }));

els.opacityRange.addEventListener('input', () => {
  applyAppearance({ opacity: Number(els.opacityRange.value) }, true);
});

const commitSize = () => {
  applyAppearance({ width: els.sizeW.value, height: els.sizeH.value }, true);
};
els.sizeW.addEventListener('change', commitSize);
els.sizeH.addEventListener('change', commitSize);

els.btnHide.addEventListener('click', () => post({ cmd: 'hide' }));

els.btnPin.addEventListener('click', () => {
  const on = !els.btnPin.classList.contains('on');
  els.btnPin.classList.toggle('on', on);
  post({ cmd: 'pin', on });
  toast(on ? '已置顶' : '已取消置顶');
});

els.refine.addEventListener('click', (event) => {
  const pill = event.target.closest('.pill');
  if (!pill || !state.lastPrompt || state.busy) return;
  const instruction = REFINE_PROMPTS[pill.dataset.refine];
  if (!instruction) return;
  startGenerate(`下面是原提示词：\n\n${state.lastPrompt}\n\n${instruction}`, 'refine');
});

els.output.addEventListener('click', () => {
  if (state.lastPrompt) {
    window.getSelection()?.collapse(els.output, 0);
  }
});

els.input.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
    event.preventDefault();
    startGenerate(els.input.value, 'new');
  }
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    if (!els.settingsSheet.hidden) { hideSheet(els.settingsSheet); return; }
    if (!els.historySheet.hidden) { hideSheet(els.historySheet); return; }
    post({ cmd: 'hide' });
  }
  if (event.key === 'c' && (event.metaKey || event.ctrlKey) && event.shiftKey) {
    event.preventDefault();
    els.btnCopy.click();
  }
});

document.addEventListener('click', (event) => {
  if (!event.target.closest('.bubble')) return;
  const tips = TIPS;
  state.tipIndex = (state.tipIndex + 1) % tips.length;
  els.bubbleText.textContent = tips[state.tipIndex];
  els.bubble.classList.remove('pop');
  void els.bubble.offsetWidth;
  els.bubble.classList.add('pop');
});

// ---------- Swift → JS ----------

window.__fish = {
  onShow() {
    els.input.focus();
    const tips = TIPS;
    state.tipIndex = (state.tipIndex + 1) % tips.length;
    els.bubbleText.textContent = tips[state.tipIndex];
  },

  start() {
    setBusy(true);
  },

  chunk(payload) {
    if (!state.busy) setBusy(true);
    const current = (els.output.querySelector('.md') || { innerHTML: '' }).innerHTML;
    // 每次追加都重渲染整段，保证结构稳定（文本量 1k 级，代价可接受）
    full += payload.text || '';
    els.output.innerHTML = `<div class="md">${renderOutline(full)}<span class="cursor"></span></div>`;
    els.output.scrollTop = els.output.scrollHeight;
  },

  done(payload) {
    const text = (payload.text || full || '').trim();
    setBusy(false);
    if (!text) {
      this.error({ message: '没有返回内容，再试一次？' });
      return;
    }
    presentPrompt(text);
    full = '';
  },

  error(payload) {
    setBusy(false);
    full = '';
    setOutputMeta('');
    els.output.innerHTML = `<div class="empty"><p class="empty-title">出错了</p><p class="empty-sub">${escapeHTML(payload.message || '未知错误')}</p></div>`;
  },

  copied(payload) {
    if (payload.ok) toast('已复制，去粘贴吧 🐟');
    else toast('复制失败，手动选一下吧');
  },

  status(payload) {
    const ok = !!payload.hasKey;
    els.dot.className = `dot ${ok ? 'ok' : 'err'}`;
    els.statusText.textContent = ok
      ? `DeepSeek 已就绪 · ${payload.source || ''}`
      : '没找到 DeepSeek 凭据 · 点 ⚙ 填一个';
    if (payload.model) els.modelText.textContent = payload.model;
  },

  pinned(payload) {
    els.btnPin.classList.toggle('on', !!payload.on);
  },

  // Swift 侧夹紧/拖拽缩放后回写真实值
  appearance(payload) {
    applyAppearance(payload || {});
  }
};

let full = '';

// 演示 / 自测入口
window.__fishDemoFill = (payload) => {
  const text = (payload && payload.text) || '';
  els.input.value = text;
  startGenerate(text, 'new');
};

// ---------- 初始化 ----------

showEmpty();
applyAppearance();
post({ cmd: 'status' });
setInterval(() => post({ cmd: 'status' }), 20000);
