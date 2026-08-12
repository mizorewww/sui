const nativePort = chrome.runtime.connectNative("com.mizore.sui.browserbridge");

nativePort.onMessage.addListener(async (request) => {
  const command = request?.userInfo ?? request;
  try {
    const tab = await xTab();
    const response = await chrome.tabs.sendMessage(tab.id, command);
    nativePort.postMessage({ id: command.id, ...response });
  } catch (error) {
    nativePort.postMessage({ id: command.id, ok: false, message: error.message });
  }
});

nativePort.onDisconnect.addListener(() => {
  console.warn("sui native bridge disconnected", chrome.runtime.lastError?.message);
});

async function xTab() {
  const tabs = await chrome.tabs.query({ url: ["https://x.com/*", "https://twitter.com/*"] });
  if (tabs.length) {
    await chrome.tabs.update(tabs[0].id, { active: true });
    return tabs[0];
  }
  const tab = await chrome.tabs.create({ url: "https://x.com/compose/post", active: true });
  await waitUntilComplete(tab.id);
  return tab;
}

function waitUntilComplete(tabId) {
  return new Promise((resolve) => {
    const listener = (id, info) => {
      if (id === tabId && info.status === "complete") {
        chrome.tabs.onUpdated.removeListener(listener);
        resolve();
      }
    };
    chrome.tabs.onUpdated.addListener(listener);
  });
}
