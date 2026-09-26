import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { SKIN_VERSION, verifySession } from "../scripts/injector.mjs";

const selectors = {
  shell: 'main:is(.main-surface, [data-app-shell-main-surface], [class*="_MainContentSurface_"])',
  sidebar: "aside.app-shell-left-panel",
  composer: ':is(.composer-surface-chrome, [class*="_ComposerLayoutRoot_"], [data-composer-surface-variant][data-composer-radius-variant])',
  nativeInput: 'textarea, [contenteditable="true"], [role="textbox"]',
  homeIcon: '[data-testid="home-icon"]',
  homeRoute: '[role="main"]:has([data-testid="home-icon"])',
  gameSource: '[data-feature="game-source"]',
  homeSuggestions: ".group\\/home-suggestions",
  projectSelector: ".group\\/project-selector",
  threadSurface: ".thread-scroll-container",
  message: ':is([data-message-author-role], [data-local-conversation-user-anchor], [data-local-conversation-final-assistant])',
  markdown: '[class*="_markdown"]',
  settingsPanel: '[data-settings-panel-slug="general-settings"]',
  appearanceRadio: 'input[name="appearance-theme"]',
  themePreview: '[data-testid="theme-preview"]',
};

function rect(width = 800, height = 600, x = 0, y = 0) {
  return { x, y, width, height, right: x + width, bottom: y + height };
}

function element({
  bounds = rect(),
  visible = true,
  style = {},
  text = "",
  closest = () => null,
} = {}) {
  return {
    isConnected: true,
    textContent: text,
    childNodes: text ? [{ nodeType: 3, textContent: text }] : [],
    children: [],
    _style: {
      display: "block",
      visibility: "visible",
      contentVisibility: "visible",
      opacity: "1",
      color: "rgb(240, 240, 240)",
      ...style,
    },
    closest,
    getBoundingClientRect: () => bounds,
    checkVisibility: () => visible,
    querySelector: () => null,
    querySelectorAll: () => [],
  };
}

function makeDom({
  shell = element(),
  sidebar = element({ bounds: rect(280, 740) }),
  composer = element({ bounds: rect(620, 80, 300, 640) }),
  composerInput = element({ bounds: rect(600, 44, 310, 650) }),
  genericMain = null,
  genericInput = null,
  genericComposerInput = element({ bounds: rect(600, 44, 310, 650) }),
  threadSurface = null,
  messages = [],
  markdownNodes = [],
  scope = { level: "L1", baseState: "thread", missingL1: [] },
  nativeWindowError = null,
} = {}) {
  if (composer) {
    composer.querySelector = (selector) => selector === selectors.nativeInput
      ? composerInput : null;
  }
  if (genericInput) {
    genericInput.querySelector = (selector) => selector === selectors.nativeInput
      ? genericComposerInput : null;
  }
  if (threadSurface) {
    const scopedNodes = new Set([...messages, ...markdownNodes]);
    threadSurface.contains = (node) => scopedNodes.has(node);
  }
  const styleNode = {};
  const document = {
    documentElement: {
      scrollWidth: 1280,
      clientWidth: 1280,
      scrollHeight: 800,
      clientHeight: 800,
      getAttribute: (name) => name === "data-dream-skin" ? "active" : null,
    },
    adoptedStyleSheets: [],
    visibilityState: "visible",
    querySelector(selector) {
      if (selector === selectors.shell) return shell;
      if (selector === selectors.sidebar) return sidebar;
      if (selector === selectors.composer) return composer;
      if (selector === selectors.homeIcon || selector === selectors.gameSource ||
          selector === selectors.homeSuggestions || selector === selectors.projectSelector ||
          selector === selectors.homeRoute) return null;
      if (selector === selectors.threadSurface) return threadSurface;
      if (selector === '[data-ds-part="main"], [data-ds-part="home"]') return genericMain;
      if (selector === '[data-ds-part="composer"]') return genericInput;
      if (selector === selectors.settingsPanel || selector === selectors.appearanceRadio ||
          selector === selectors.themePreview) return null;
      return null;
    },
    querySelectorAll(selector) {
      if (selector === selectors.message) return messages;
      if (selector === selectors.markdown) return markdownNodes;
      return [];
    },
    getElementById: (id) => id === "codex-dream-skin-style" ? styleNode : null,
  };
  const dom = {
    document,
    window: {
      __CODEX_DREAM_SKIN_STATE__: {
        version: SKIN_VERSION,
        themeId: "fixture-theme",
        revision: "fixture-revision",
        styleMode: "style",
        styleNode,
        scope,
      },
    },
    innerWidth: 1280,
    innerHeight: 800,
    getComputedStyle: (node) => node?._style ?? {},
  };
  return { dom, nativeWindowError };
}

function makeSession(options = {}) {
  const { dom, nativeWindowError } = makeDom(options);
  return {
    target: { id: "fixture-target" },
    async evaluate(expression) {
      return vm.runInNewContext(expression, dom);
    },
    async send(method) {
      assert.equal(method, "Browser.getWindowForTarget");
      if (nativeWindowError) {
        throw nativeWindowError;
      }
      return {
        windowId: 41,
        bounds: { width: 1280, height: 800, windowState: "normal" },
      };
    },
  };
}

async function verify(options = {}) {
  return verifySession(makeSession(options), "fixture-theme", "fixture-revision");
}

test("macOS L1 thread requires a native composer input or scoped conversation content", async () => {
  const error = Object.assign(new Error("Browser window not found (-32000)"), {
      cdpCode: -32000,
  });
  const validComposer = await verify({ nativeWindowError: error });
  assert.equal(validComposer.composerPass, true);
  assert.equal(validComposer.checks.threadContentPass, true);
  assert.equal(validComposer.nativeWindow.status, "unsupported");
  assert.equal(validComposer.pass, true,
    "A visible native composer may use the unsupported Browser-domain fallback.");

  const emptyShell = await verify({
    composer: null,
    composerInput: null,
    genericInput: null,
    threadSurface: null,
    messages: [],
    markdownNodes: [],
    nativeWindowError: new Error("'Browser.getWindowForTarget' wasn't found (-32601)"),
  });
  assert.equal(emptyShell.scope.baseState, "thread");
  assert.equal(emptyShell.scope.level, "L1");
  assert.equal(emptyShell.shell.visible, true);
  assert.equal(emptyShell.sidebar.visible, true);
  assert.equal(emptyShell.composer, null);
  assert.equal(emptyShell.genericInput, null);
  assert.equal(emptyShell.visibleMessageCount, 0);
  assert.equal(emptyShell.visibleMarkdownCount, 0);
  assert.equal(emptyShell.nativeWindow.status, "unsupported");
  assert.equal(emptyShell.checks.threadContentPass, false);
  assert.equal(emptyShell.pass, false,
    "The exact empty-thread symptom must fail even when native window lookup is unsupported.");
});

test("a composer shell without a native input is not thread readiness evidence", async () => {
  const result = await verify({
    composerInput: null,
    genericInput: null,
    threadSurface: null,
    messages: [],
    markdownNodes: [],
  });
  assert.equal(result.composer.visible, true);
  assert.equal(result.composerInput, null);
  assert.equal(result.composerPass, false);
  assert.equal(result.checks.threadContentPass, false);
  assert.equal(result.pass, false);
});

test("workspace-panel token classes cannot supply the conversation input", async () => {
  const panelSelector = '[class~="bg-token-main-surface-primary"][class~="border-l"]';
  const result = await verify({
    composer: null,
    genericInput: element(),
    genericComposerInput: element({
      closest: (selector) => selector.includes(panelSelector) ? {} : null,
    }),
  });
  assert.equal(result.pass, false);
  assert.equal(result.genericComposerPass, false);
});

test("visible semantic history is accepted, while dialog and side-panel content is ignored", async () => {
  const history = element({ text: "Existing turn" });
  const visibleHistory = await verify({
    composer: null,
    composerInput: null,
    threadSurface: element({ bounds: rect(900, 650, 320, 80) }),
    messages: [history],
    markdownNodes: [],
  });
  assert.equal(visibleHistory.visibleMessageCount, 1);
  assert.equal(visibleHistory.checks.threadContentPass, true);
  assert.equal(visibleHistory.pass, true);

  const sidePanelMessage = element({ closest: () => ({}) });
  const ignoredSidePanel = await verify({
    composer: null,
    composerInput: null,
    threadSurface: element({ bounds: rect(900, 650, 320, 80) }),
    messages: [sidePanelMessage],
    markdownNodes: [],
  });
  assert.equal(ignoredSidePanel.visibleMessageCount, 0);
  assert.equal(ignoredSidePanel.visibleMarkdownCount, 0);
  assert.equal(ignoredSidePanel.checks.threadContentPass, false);
  assert.equal(ignoredSidePanel.pass, false);

  const sidePanelInput = element({ closest: () => ({}) });
  const sidePanelComposer = element();
  sidePanelComposer.querySelector = (selector) => selector === selectors.nativeInput
    ? sidePanelInput : null;
  const ignoredSidePanelInput = await verify({
    composer: null,
    composerInput: null,
    genericInput: sidePanelComposer,
    genericComposerInput: sidePanelInput,
    threadSurface: null,
    messages: [],
    markdownNodes: [],
  });
  assert.equal(ignoredSidePanelInput.genericInput.visible, true);
  assert.equal(ignoredSidePanelInput.genericComposerInput.visible, true);
  assert.equal(ignoredSidePanelInput.genericComposerPass, false);
  assert.equal(ignoredSidePanelInput.checks.threadContentPass, false);
  assert.equal(ignoredSidePanelInput.pass, false);
});

test("settings and home routes keep their existing readiness rules", async () => {
  const settings = await verify({
    scope: { level: "L0", baseState: "settings", missingL1: [] },
    shell: null,
    sidebar: null,
    composer: null,
    composerInput: null,
  });
  assert.equal(settings.pass, false,
    "The fixture intentionally has no settings anchor; the thread gate must not make it pass.");
  assert.equal(settings.checks.threadContentPass, true,
    "Non-thread routes do not require composer or conversation content.");
});
