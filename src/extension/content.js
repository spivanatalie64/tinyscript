/* Tinyscript Content Script
   Intercepts script tags and replaces JS with Tinyscript */

"use strict";

let gOverrideAllScripts = false;

// Run Tinyscript code from a source string
function runTinyscript(source, element) {
  try {
    const result = tinyscriptRun(source);
    if (element && element.dataset.tsResult) {
      element.dataset.tsResult = JSON.stringify(tsVal(result));
    }
  } catch (e) {
    console.error('[Tinyscript] Error:', e);
    if (element) {
      element.dispatchEvent(new CustomEvent('tinyscript-error', { detail: { error: e.message } }));
    }
  }
}

// Process a single script element
function processScript(script) {
  if (script.dataset.tinyscriptProcessed) return;
  script.dataset.tinyscriptProcessed = 'true';

  const type = script.type || 'text/javascript';

  if (type === 'text/tinyscript' || gOverrideAllScripts) {
    if (script.src) {
      // External script - fetch and run
      fetch(script.src)
        .then(r => r.text())
        .then(code => runTinyscript(code, script))
        .catch(e => console.error('[Tinyscript] Failed to fetch:', script.src, e));
    } else {
      // Inline script
      runTinyscript(script.textContent, script);
    }

    // Prevent normal execution
    script.type = 'text/blocked-by-tinyscript';
    return true;
  }
  return false;
}

// Intercept all script elements
function interceptScripts() {
  document.querySelectorAll('script').forEach(processScript);
}

// Watch for dynamically added scripts
const observer = new MutationObserver((mutations) => {
  for (const mutation of mutations) {
    for (const node of mutation.addedNodes) {
      if (node.tagName === 'SCRIPT') processScript(node);
      if (node.querySelectorAll) {
        node.querySelectorAll('script').forEach(processScript);
      }
    }
  }
});

// Intercept event handlers (onclick, onload, etc.)
function interceptEventHandlers() {
  const handlerAttrs = ['onclick', 'onload', 'onchange', 'onsubmit',
    'onmouseover', 'onmouseout', 'onkeydown', 'onkeyup', 'onkeypress',
    'onfocus', 'onblur', 'onscroll', 'onresize', 'onerror'];

  // Override setAttribute to catch handler assignment
  const origSetAttr = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function(name, value) {
    if (handlerAttrs.includes(name.toLowerCase())) {
      // Wrap in a function that runs Tinyscript
      const wrapped = function(event) {
        runTinyscript(value, this);
      };
      return origSetAttr.call(this, name, wrapped);
    }
    return origSetAttr.call(this, name, value);
  };
}

// Block JavaScript: declarativeNetRequest to block .js files
function setupBlocking() {
  if (typeof browser !== 'undefined' && browser.runtime) {
    browser.runtime.sendMessage({ action: 'blockJS' });
  }
}

// Initialize
function init() {
  // Check storage for override setting
  if (typeof browser !== 'undefined' && browser.storage) {
    browser.storage.local.get('overrideAll').then(r => {
      gOverrideAllScripts = r.overrideAll || false;
      start();
    }).catch(() => start());
  } else {
    start();
  }
}

function start() {
  // Block JS files
  setupBlocking();

  // Intercept existing scripts (need to wait for DOM but be early)
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      interceptScripts();
      interceptEventHandlers();
    });
  } else {
    interceptScripts();
    interceptEventHandlers();
  }

  // Observe for dynamic scripts
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true
  });

  // Also intercept immediately for scripts already parsed
  setTimeout(interceptScripts, 0);

  console.log('[Tinyscript] Extension active — JavaScript replaced with Tinyscript');
}

init();
