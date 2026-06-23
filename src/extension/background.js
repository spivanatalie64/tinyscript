/* Tinyscript Background Script */

"use strict";

// Block JavaScript files when override is enabled
function blockJS(details) {
  return { cancel: true };
}

// Listen for messages from content script
browser.runtime.onMessage.addListener((msg, sender) => {
  if (msg.action === 'blockJS') {
    // Enable JS blocking
    browser.webRequest.onBeforeRequest.addListener(
      blockJS,
      { urls: ["*://*/*.js", "*://*/*.js?*"], types: ["script"] },
      ["blocking"]
    );
  }
});

// Handle toolbar button click
browser.browserAction.onClicked.addListener((tab) => {
  browser.tabs.sendMessage(tab.id, { action: 'toggleOverride' });
});

console.log('[Tinyscript] Background script loaded');
