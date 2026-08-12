const extensionAPI = globalThis.browser ?? globalThis.chrome;
const nativePort = extensionAPI.runtime.connectNative("com.mizore.sui.browserbridge");

extensionAPI.runtime.onMessage.addListener((message) => {
  if (message?.type === "sui-content-ready") return Promise.resolve({ ok: true });
  return undefined;
});

nativePort.onMessage.addListener(async (request) => {
  const source = request?.userInfo ?? request ?? {};
  if (!source.id || !["prepareX", "postX"].includes(source.command)) return;
  const command = {
    id: String(source.id ?? ""),
    command: String(source.command ?? ""),
    ...(typeof source.text === "string" ? { text: source.text } : {})
  };
  try {
    const tab = await xTab();
    const response = await sendToXPage(tab.id, command);
    nativePort.postMessage({
      id: command.id,
      ok: response?.ok === true,
      ...(response?.message
        ? { message: response.message }
        : response?.ok === true
          ? {}
          : { message: "Safari 没有收到 X.com 页面脚本的有效响应。" })
    });
  } catch (error) {
    nativePort.postMessage({ id: command.id, ok: false, message: errorText(error) });
  }
});

nativePort.onDisconnect.addListener(() => {
  console.warn("sui native bridge disconnected", extensionAPI.runtime.lastError?.message);
});

async function xTab() {
  const tabs = await extensionAPI.tabs.query({
    url: ["https://x.com/compose/post*", "https://twitter.com/compose/tweet*"]
  });
  if (tabs.length) {
    await extensionAPI.tabs.update(tabs[0].id, { active: true });
    await delay(350);
    return tabs[0];
  }
  const tab = await extensionAPI.tabs.create({ url: "https://x.com/compose/post", active: true });
  await delay(350);
  return tab;
}

async function sendToXPage(tabId, command) {
  const attempts = command.command === "prepareX" ? 80 : 1;
  let lastError;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const response = await extensionAPI.tabs.sendMessage(tabId, command);
      if (response?.ok === true || response?.message) return response;
    } catch (error) {
      lastError = error;
    }
    if (attempt + 1 < attempts) await delay(500);
  }
  if (lastError) throw lastError;
  return { ok: false, message: "Safari 没有收到 X.com 页面脚本的有效响应。" };
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function errorText(error) {
  if (typeof error?.message === "string" && error.message) return error.message;
  if (typeof error?.localizedDescription === "string" && error.localizedDescription) return error.localizedDescription;
  const text = String(error ?? "");
  return text && text !== "[object Object]" ? text : "Safari 扩展无法访问当前 X.com 页面。";
}
