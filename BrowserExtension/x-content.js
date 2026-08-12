const contentAPI = globalThis.browser ?? globalThis.chrome;

// Loading an X page must wake Safari's MV3 background worker so it can open
// the native-messaging port before the containing app dispatches a command.
const readyPing = contentAPI.runtime.sendMessage({ type: "sui-content-ready" });
if (readyPing?.catch) readyPing.catch(() => {});

if (globalThis.browser) {
  contentAPI.runtime.onMessage.addListener((request) =>
    handle(request).catch((error) => ({ ok: false, message: errorText(error) }))
  );
} else {
  contentAPI.runtime.onMessage.addListener((request, _sender, sendResponse) => {
    handle(request).then(sendResponse).catch((error) => sendResponse({ ok: false, message: errorText(error) }));
    return true;
  });
}

async function handle(request) {
  if (location.pathname.startsWith("/i/flow/login") || document.querySelector('input[autocomplete="username"]')) {
    return { ok: false, message: "请先在浏览器中登录 X。" };
  }

  const composer = await findComposer();
  if (!composer) return { ok: false, message: "没有找到 X Post 输入框。" };
  if (request.command === "prepareX") return { ok: true };
  if (request.command !== "postX" || !request.text) return { ok: false, message: "无效的发布命令。" };

  composer.focus();
  document.execCommand("selectAll", false, null);
  document.execCommand("insertText", false, request.text);
  composer.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: request.text }));

  const postButton = await findEnabledPostButton();
  if (!postButton) {
    return { ok: false, message: "Post 按钮当前不可用。" };
  }
  postButton.click();
  return { ok: true };
}

async function findComposer() {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    const composer = document.querySelector('[data-testid="tweetTextarea_0"][contenteditable="true"]');
    if (composer) return composer;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return null;
}

async function findEnabledPostButton() {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    const button = document.querySelector('[data-testid="tweetButtonInline"], [data-testid="tweetButton"]');
    if (button && !button.disabled && button.getAttribute("aria-disabled") !== "true") return button;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return null;
}

function errorText(error) {
  return typeof error?.message === "string" && error.message
    ? error.message
    : "X.com 页面脚本执行失败。";
}
