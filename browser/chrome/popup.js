// 从本地存储读取接管开关，并保存每次切换。
const toggle = document.querySelector("#enabled");

chrome.storage.local.get({ enabled: true }).then(({ enabled }) => {
  toggle.checked = enabled;
  toggle.disabled = false;
}).catch((error) => console.error("读取接管设置失败。", error.message));

toggle.addEventListener("change", async () => {
  toggle.disabled = true;
  try {
    await chrome.storage.local.set({ enabled: toggle.checked });
  } catch (error) {
    toggle.checked = !toggle.checked;
    console.error("保存接管设置失败。", error.message);
  } finally {
    toggle.disabled = false;
  }
});

document.getElementById("label").textContent = chrome.i18n.getMessage("takeOver");

// 每次打开弹窗探测一次宿主，探测完成前状态行留空。
const status = document.getElementById("status");
chrome.runtime.sendNativeMessage("com.yafaya.rainkeep", { type: "hello" })
  .then((reply) => reply?.ok === true, (error) => {
    console.error("拾雨宿主连接失败。", error.message);
    return false;
  })
  .then((connected) => {
    status.className = connected ? "ok" : "fail";
    status.textContent = chrome.i18n.getMessage(connected ? "hostConnected" : "hostNotConnected");
  });
