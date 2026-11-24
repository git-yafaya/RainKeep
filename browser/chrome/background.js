// 接管网页下载，宿主失败时把下载交回原浏览器。
const browserRetries = new Map();
const hostName = "local.downloader";

async function hello() {
  try {
    const reply = await chrome.runtime.sendNativeMessage(hostName, { type: "hello" });
    if (reply?.ok !== true) throw new Error(reply?.error || "宿主未确认连接");
  } catch (error) {
    console.error("下载器宿主连接失败。", error.message);
  }
}

chrome.runtime.onInstalled.addListener(hello);
chrome.runtime.onStartup.addListener(hello);

// 保存当前 URL 和浏览器分配的下载 ID，区分同时点击的相同链接。
async function returnToBrowser(url) {
  const retry = chrome.downloads.download({ url });
  browserRetries.set(retry, url);
  try {
    await retry;
  } catch (error) {
    browserRetries.delete(retry);
    throw error;
  }
}

// onCreated 和 download() 的完成顺序取决于浏览器。
async function isBrowserRetry(item) {
  for (const [retry, url] of browserRetries) {
    if (url === item.url && await retry.catch(() => undefined) === item.id) {
      browserRetries.delete(retry);
      return true;
    }
  }
  return item.byExtensionId === chrome.runtime.id;
}

// 取消后只传递目标站点的 Cookie 和文件名，不传本机目录。
async function takeOver(item) {
  const url = item.finalUrl || item.url;
  if (!/^https?:\/\//i.test(item.url) || !/^https?:\/\//i.test(url) ||
      item.state !== "in_progress" || await isBrowserRetry(item)) return;
  const { enabled } = await chrome.storage.local.get({ enabled: true });
  if (!enabled) return;

  await chrome.downloads.cancel(item.id);
  try {
    // 小文件可能在取消前已经下载完毕，应保留原文件和历史记录。
    const [current] = await chrome.downloads.search({ id: item.id });
    if (current?.state === "complete") return;
    await chrome.downloads.erase({ id: item.id });
    const cookies = await chrome.cookies.getAll({ url });
    const response = await chrome.runtime.sendNativeMessage(hostName, {
      url,
      referrer: item.referrer || undefined,
      filename: item.filename?.split("/").pop() || undefined,
      cookies: cookies.map(({ name, value }) => name + "=" + value).join("; ") || undefined,
      userAgent: navigator.userAgent,
    });
    if (response?.ok !== true) throw new Error(response?.error || "宿主未确认接管");
  } catch (error) {
    console.error("下载器接管失败，交回浏览器。", error.message);
    await returnToBrowser(item.url);
  }
}

chrome.downloads.onCreated.addListener((item) => {
  takeOver(item).catch((error) => console.error("浏览器下载操作失败。", error.message));
});
