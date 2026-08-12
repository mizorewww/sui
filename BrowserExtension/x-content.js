chrome.runtime.onMessage.addListener((request, _sender, sendResponse) => {
  handle(request).then(sendResponse).catch((error) => sendResponse({ ok: false, message: error.message }));
  return true;
});

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

  const postButton = document.querySelector('[data-testid="tweetButtonInline"], [data-testid="tweetButton"]');
  if (!postButton || postButton.disabled || postButton.getAttribute("aria-disabled") === "true") {
    return { ok: false, message: "Post 按钮当前不可用。" };
  }
  postButton.click();
  return { ok: true };
}

async function findComposer() {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const composer = document.querySelector('[data-testid="tweetTextarea_0"][contenteditable="true"]');
    if (composer) return composer;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return null;
}

