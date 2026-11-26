# 浏览器下载接管

用户装法见项目根目录 README "接管浏览器下载": 设置里点 "连接", 把访达里选中的 "拾雨扩展" 拖进浏览器扩展页 (要开 "开发者模式"). 扩展放在 `~/Library/Application Support/Rainkeep/拾雨扩展.bundle`, 浏览器从这里加载.

- 扩展 ID 固定为 `fhfcdggihhigpphnfagldelhdcehnkoa` (manifest 里的 `key` 决定). 工具栏里的 "接管下载" 默认开启, 关闭后由浏览器直接下载.
- App 每次启动把宿主清单写进各浏览器数据目录的 `NativeMessagingHosts/com.yafaya.rainkeep.json`, 指向 App 包里的 `RainkeepHost`; App 挪了位置下次启动自动更新.
- 扩展安装和浏览器启动时发一条 `{"type":"hello"}`, 宿主记到 `~/Library/Application Support/Rainkeep/extension.json`, 设置里据此显示 "已连接". 扩展被卸载后这条记录不会消失.

仅接管 HTTP(S) 下载. 宿主失败时浏览器重新请求原链接. 依赖 POST 正文或只能访问一次的链接可能无法重放. 宿主在本机通过 URL 传递站点 Cookie, 请避免记录或分享完整的 scheme URL.

在项目根目录可用一条测试消息检查宿主, dry-run 会跳过启动 App. 输出应以 `0b 00 00 00` 开头, 后面是 `{"ok":true}`.

```sh
printf '\035\000\000\000%s' '{"url":"https://example.org"}' | RAINKEEP_HOST_DRY_RUN=1 .build/Rainkeep.app/Contents/MacOS/RainkeepHost | hexdump -C
```
