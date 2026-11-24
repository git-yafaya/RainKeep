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
