# 内置 Browser 工具行为实测笔记

针对 SPL5 这类"大量生成控件 + DataTables 内嵌列表"的页面的实测结论。
通用浏览器语义见 `browser-use:control-in-app-browser` skill，这里只记 SPL5 场景下的差异。

## 各 query kind 到底返回什么

| kind | 返回 | SPL5 场景下的要点 |
|---|---|---|
| `inspect` | 当前页可交互元素快照 + semanticTree | 一次返回整页，输出很大；需要判断 select2 当前选中项时看 combobox 下 option 的 `selected: true` |
| `query(kind="text")` | 可见文本 | **不反映 input/textarea 的当前值**；隐藏页签内容可能取不到；判断"表格有没有行"不可靠 |
| `query(kind="dom")` | 第一个匹配元素的 outerHTML | **核对表单真实值的唯一可靠手段**：input 的 `value`、textarea 的内容、radio 的 `checked`、option 的 `selected` 都能看到；只返回第一个匹配元素，复杂后代选择器不支持。⚠️ **但 `value`/`checked` 是 HTML 属性，不是 live property**——JS 用 `.val()` 写入的值不会反映到 outerHTML 里（见下面 numberFormat 一节） |
| `query(kind="editable")` | 可编辑控件列表（带 `attributes.value`） | **只列当前激活页签**的控件；切页签后要重新查；`attributes.value` 对 textarea 不给值；⚠️ 它读的是 HTML 属性而非 live property，**不能当作读当前值的可靠来源**（见下面 numberFormat 一节） |
| `query(kind="semantic")` | 按可见文本匹配的元素 | 找"页面当前显示的是哪个选项"最可靠；比在 semanticTree 里翻快 |
| `query(kind="console")` | 页面级 console / 未捕获异常 | SPL5 保存后常见的 `TypeError: Cannot read properties of null (reading 'panelXXXXXXX')` 就是这么看 |
| `query(kind="network")` | 请求摘要（方法/URL/状态/耗时） | 确认 `query12m/*` 这类 XHR 有没有被调用、状态码是否 200；**看不到请求体和响应体** |

## 实操顺序

1. `inspect` 一次拿页面骨架和可点元素。
2. 要填值：优先 `fill`（会先清空）；码表下拉用 `select_option`。
3. 要**核对**值：用 `query(kind="dom")`，不要用 `kind="text"`。
4. 要判断某行是否存在：切到对应页签 → `query(kind="dom", selector="#panelXXXTable tbody")`，
   看返回的 HTML 里有没有 `<tr>`。

## 坑

- **跨 frame 的弹窗按钮：必须用语义查询拿 ref 再点**（2026-11-10 实测，最容易踩）。
  SPL5 的长文本弹窗把「确定/取消」放在 `.ui-dialog-footer` 里，但
  `.ui-dialog` 容器选择器**匹配不到**它们：
  - `query(kind="dom", selector=".ui-dialog button")` → 只返回 `button.ui-dialog-close`（×关闭）。
  - `query(kind="dom", selector="button.ui-dialog-autofocus")` → 能取到 HTML，
    但 **`click` 它不生效**（点了没反应，弹窗还在）。
  - **可靠做法**：`query(kind="semantic", text="确定")` → 返回带 `frame` 的 opaque ref →
    `click(ref)`。语义查询给的 ref 指向那个 frame 里**真正可见**的按钮，一次点中。
  - 同理，iframe 里的 `input[type=file]`、上传弹窗里的控件，主文档 selector 都查不到，
    要靠 `inspect` 拿到 iframe 内元素的 ref。
- **select_option 超时**：change 绑定后会大面积重绘的下拉（如评标办法 `pfff.pbbfCode`，
  触发 `resetPbbf()` + `changePfbf_A01_A02()`）可能耗时几百秒。超时**不等于失败**，
  改用"切页签 → 重新取 ref → 再操作"，或直接用 dom 核对最终值。
- **refs 会过期**：reload / navigate 之后旧的 ref 全部失效，要重新 `inspect`。
- **一次一个调用**：Browser 动作共享页面/快照状态，并发调用会互相污染。
- **上传控件在 iframe**：主文档 `query(kind="dom", selector="input[type=file]")` 查不到，
  要拿 iframe 内元素的 ref。
- **底部动作按钮可能没有稳定 id**：SPL5 的「暂存/保存/关闭」常是裸 `<button>`，
  `query(kind="semantic", text="保存")` 会误匹配到表单 label（页面上有含"保存"二字的字段）。
  可靠做法：`screenshot` 看清按钮条像素位置 → `click(input={position:{x,y}})` 按坐标点。
- **readonly textarea 不能 fill**：SPL5 长文本走弹窗（见 `spl5-frontend-map.md`）。
- **"操作成功"提示可能不显示**：保存后页面独立打开时 `window.opener` 为空，
  `actionBc()` 里的 `window.opener.panelXXX.lpImpl.refresh()` 抛 TypeError，
  整个回调链断掉，连成功提示也没了。**这不代表保存失败**，以重新加载后的回显和查库为准。
- **别在同一个表单里凭感觉填**：先用生成的 JSP 拿到准确 name，再填，避免把保证金填成副本数量这类串位。
- **长任务中途会掉登录态 / 撞 502**：SPL5 测试环境的 session 有有效期，
  且**测试环境会不定期发版，发版重启期间 nginx→应用之间会短暂不通**。
  现象有两种，看到哪一种要分清：
  - 被 **302 重定向到 `/login`** → session 过期。账号框会预填上次登录的机构名。
    这时**必须让用户重新登录**（要密码+验证码，不要自己尝试登录，也不要向用户索要密码）。
  - 页面显示 **502 Bad Gateway** → **多半是发版重启**（不是崩溃！）。
    **先按"发布重启"处理，别往 OOM/链路故障方向猜**。等 1~2 分钟重试。
    需要确认时用 HTTP 直接探站点，别只看浏览器：
    ```powershell
    Invoke-WebRequest -Uri '<业务URL>' -TimeoutSec 20 -UseBasicParsing -AllowInsecureRedirect
    ```
    返回 200 → 站点是好的，问题在浏览器会话；仍 502 → 应用侧确实在重启中，等一会儿再试。
    ⚠️ 站点会 302 到 http，**不加 `-AllowInsecureRedirect` 会直接报错**，别误判成站点不可用。
    深挖时：SSH 到应用机 `curl 127.0.0.1:<应用端口>`，返回 302/200 就说明**应用本身是好的**，
    502 出现在网关到应用这一跳；应用日志里满屏外网接口 ConnectTimeoutException **是噪声不是根因**。
- **502 期间不要下业务结论**：页面根本没渲染，此时"找不到按钮/面板不存在"都是假象。
  重试到页面正常渲染（`inspect` 能拿到表单元素）再继续。
  ⚠️ **发布重启不会丢已提交的数据**（本轮实测暂存的记录完好），恢复后从中断处接着做。
- **`numberFormat` 金额/数字字段（`.numberFormat()`）：`fill` / `type` 都不可靠**
  - `jquery.z.adhoc.js` 的 `numberFormat` 绑定 `focus → select()`、`blur → formatInput`，
    且用 `.val()`（**property**）写值。
  - 后果一：`fill` 会先清空，但 `focus` 里的 `select()` 又把光标选中，**填进去的值会追加到旧值后面**
    （实测填 `1000000` 变成 `10000001000000`）；`type` 同样只追加。
  - 后果二：`query(kind="dom")` 读到的 `value=""` **是假的**——outerHTML 里的 `value` 是 HTML 属性，
    而插件写的是 property。**别据此判定"没填进去"**。
  - **可靠的改值姿势**：`click` 聚焦 → `press_key{key:"a", modifiers:["Control"]}` 全选
    → `press_key{key:"Backspace"}` 清空 → `type` 新值 → 点别处 blur 让它格式化。
    ⚠️ `press_key{key:"Control+a"}` **无效**，必须拆成 `key:"a"` + `modifiers:["Control"]`。
  - **可靠的读值姿势**：**只有 `screenshot` 可靠**（裁剪该 input 区域看渲染出来的文本）。
    ⚠️ `query(kind="editable")` 的 `attributes.value` **也不可靠**（2026-11-10 实测：
    `pfff.jsf` 页面预填 `0`，editable 读出来是空值）——它读的是 HTML 属性，不是 live property。
    `query(kind="dom")` 对 **textarea 读不到内容**（内容是子节点，工具摘不出来），
    `kind="text"` 对 readonly textarea 也返回空 → 长文本只能靠截图或查库核对。
