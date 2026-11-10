# 案例

真实跑通的案例，按"遇到什么 → 怎么判断 → 怎么做"组织。新任务先扫一眼标题找最接近的那个。

---

## 案例 A：完整录入闭环（汕尾 暗标标段）

**场景**：在 `test.swggzyjy.rongzhiwang.com` 为项目 SWJG2026-0014 录入一条建设工程标段并确认落库。
**结果**：标段 id `7ebe5a4968b74ef0b3f86bd22d11636b`，父表 + 四张评审子表 + 招标文件附件全部落库，刷新后逐项回显正确。

### A1. 先解决"用哪个浏览器"

| 尝试 | 结果 | 判断 |
|---|---|---|
| 本机 Chrome 开远程调试，`127.0.0.1:9222` | 端口不可达 | 放弃 |
| Playwright MCP（独立无登录态 profile） | 访问该站点跳 `/login` | 放弃 |
| MiniMax 内置 Browser（`mcp_browser`） | 用户手动登录后正常打开目标页 | **用这个** |

**教训**：需要登录的 SPL5 站点，只有内置 Browser 能复用用户登录态。
别在另外两条路上耗轮次——它们不共享会话，症状是"能访问但跳登录页"。

### A2. 定位控件（不靠肉眼）

```powershell
# 生成的 JSP 里一次拿全所有稳定 id
Select-String -Path '...\views\jyzxt\jsgcjy\gkzb\jysq\jsgczbxmbdbjcly.jsp' -Pattern 'query12m/|panel\d{9}|IE-\w+-|action\d{12}'
```

得到的锚点：

| 用途 | selector |
|---|---|
| 切页签 | `a[href='#tab180590082']`（资格评审）、`a[href='#tab180638754']`（详细评审）、`a[href='#tab0a15eg2a86c9']`（定标配置） |
| 内嵌表「新增」 | `#action166334845`（资格）、`#action176055052`（形式）、`#action743941718`（技术）、`#action556142065`（商务） |
| 动作按钮 | `#action09bje8ifhkgf`（暂存）、`#action0a5f6ihfb866`（上传招标文件）、`#action0a0259ef61c3`（保存） |
| 保存确认框 | `button.confirm` |
| 核对某个面板 | `query(kind="dom", selector="#panel158703939Table tbody")` |

### A3. 实际踩到的四个坑

1. **`select_option` 对 `pfff.pbbfCode` 超时 ~275 秒**。
   因为 change 绑定后 `resetPbbf()` + `changePfbf_A01_A02()` 会重建大量 DOM。
   **超时不等于失败**：切到别的页签再切回来取新 ref，操作照样生效。
2. **用错 ref 把保证金填成了副本数量**（numberFormat 显示 "2"）。
   教训：`fill` 前先 `query(kind="editable")` 看清 `name` 和 `attributes.value` 再动手。
3. **怀疑"内嵌列表改了 DOM 但没同步行数据，导致提交不了"**。
   查 `jquery.z.submitButton.js` 后确认：`fetchFormData` 直接 `form.serializeArray()`，
   **DOM 里的 input 名字和值对就会被提交**，不存在额外的同步步骤。
   这个怀疑方向是对的（避免了瞎改代码），但结论是"不用同步"。
4. **长文本弹窗写入后内容变成两份**。
   弹窗会**预填旧值**再整体覆盖，在其后接着写就存成两份。
   `query(kind="dom")` 看 textarea 原始 HTML 才能发现——`query(kind="text")` 看不出来。

### A4. 保存后的假象

点「保存」→ 确认框点「是」→ 控制台报：

```
TypeError: Cannot read properties of null (reading 'panel444620557')
```

来自 `actionBc()` 里的 `window.opener.panel444620557.lpImpl.refresh()`——
页面是独立打开的、没有 opener。**这是前端回调缺陷，不是保存失败**，
连"操作成功"提示都没了。此时唯一可靠的判据是重新加载 + 查库。

### A5. 推翻自己的一次误判

首轮保存后查 `query12m/*` 返回空，一度判"四个评审子表没落库"。
**错在查错了表**：面板 `query12m/jsyqb` 对应的是 `jsgczbxmjsyq`，
而 `jsgczbxmtbjsyqb` 是另一组实体（技术要求表）。
直连库后确认四张表各 1 行、内容完全正确。

**教训**：页面/接口返回空时，先用 `Abstract*.java` 的 `@OneToMany(targetEntity=...)`
反查真实表名，再去查；不要凭名字猜。

### A6. 验库

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dbq.ps1 -ProjectRoot 'D:\zsoft\汕尾公共资源\code-swggzyjy' `
  -Sql "SELECT bdmc, sfab, sfzc, deleted FROM jsgczbxmbd WHERE id='7ebe5a4968b74ef0b3f86bd22d11636b'"
```

注意 `sfab`/`sfzc`/`deleted` 是 `bit(1)`，**直接 SELECT 得到 "1"/"0"**；
一旦套进 `CONCAT`/`IFNULL` 就会打印成空白，必须 `CAST(x AS UNSIGNED)`。

最后刷新页面，用 `query(kind="dom")` 逐个面板核对原始 HTML，确认 textarea 是单份内容。

---

## 案例 B：排查"页面列表空，但库里明明有数据"

**症状**：某个内嵌列表刷新后不显示行，但查询接口返回 200。

**排查顺序**（不要跳步）：

1. **确认接口确实返回了数据**：查 `query(kind="network", filter="query12m")` 看状态码。
2. **确认面板激活**：内嵌表是异步渲染的，`query(kind="editable")` 只列当前激活页签。
   先 `click(selector="a[href='#tabXXX']")` 切过去。
3. **看原始 DOM**：`query(kind="dom", selector="#panelXXXTable tbody")`。
   - 返回里有 `<tr>` → 数据到了前端，是渲染/列定义问题；
   - 只有表头 → 服务端没返回行。
4. **反查真实表名与关联列**：`Abstract*.java` 的 `@OneToMany(mappedBy="ssxmbd")`
   → 子表列 `ssxmbdId`；同时确认没被 `ssgzmxId` 误导。
5. **直接查库**：`SELECT COUNT(*) FROM <真实表> WHERE ssxmbdId='<id>'`。
   库里有 → 第 3 步的问题；库里没有 → 是保存/校验环节的问题。

---

## 案例 C：录入/编辑的入口选择

新建和编辑走的 URL 不一样，**参数缺失会让服务端跳过校验**：

| 入口 | URL 形态 | 风险 |
|---|---|---|
| 父级页 `openBdbj` 按钮 | `cu/<id>?zbxmlx=A01&zblx=07&dbms=03` | 正常 |
| 父级列表行内「编辑」 | `cu/{{entity.id}}?` | **缺参数 → 假落库** |
| 手工拼 URL | 任意 | **缺参数 → 假落库** |

缺 `zbxmlx`/`zblx` 时 `getShowAllTab(null,null)` 返回 false，
"至少录入1个资格条件""评标委员会人数5~50"等整段校验不会被执行——
数据存进去了，但没人校验过。

**做法**：优先用平台自己的入口；实在要手拼，就照 `custom.jsp` 里 `openWindow` 的写法补全参数。
