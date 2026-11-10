---
name: spl5-browser-test
description: |
  用内置浏览器在 SPL5（生产线5）公共资源交易平台上定位控件、录入并验证测试数据。
  触发场景：用户要求"用浏览器测试/录入/填报"某个 SPL5 业务单据（标段、交易申请、
  评标办法、资格条件、招标文件等），或问"SPL5 这个页面怎么填、控件 id 在哪、
  字段 name 叫什么、内嵌列表怎么新增行、保存后怎么确认落库"，或排查"SPL5 页面
  保存了但列表不显示/数据不见了"。也用于任何 SPL5 项目的浏览器端验收与造数。
  不用于 SPL5 的代码生成、模型校验、DDL 与单测（用 spl5-code-generator /
  spl5-model-validator / spl5-db-engineer），也不用于非 SPL5 平台的通用网页自动化。
---

# SPL5 浏览器测试与数据录入

SPL5 页面是**代码生成**出来的：控件 id、字段 name、面板结构在生成的 JSP 里写死，
实体字段↔列名在 `.et` 模型里写死，关联关系在 `generated/Abstract*.java` 里写死。
所以**别在页面里盲找控件，先 grep 仓库**，几分钟就能拿到全部稳定 id。

## Inputs to collect

- 目标 URL、父级单据与子单据（汕尾建设工程的典型组合见 `spl5-bid-section-entry` skill）
- 业务口径来源：项目总投资、标准工期、交易类型等**必须从父级单据读**，用户口述值只作交叉校验
- 是否需要确认落库：用户说"录入/保存/落库"就要查库核对（见 Procedure 第 6 步）
- 若页面需要登录而当前 Browser 无登录态：让用户在同一 Browser 标签页登录，不要代填凭据

## Procedure

### 1. 先读模型，再动浏览器

在仓库里定位三处，它们能一次性回答"控件在哪、字段叫什么、数据落在哪张表"：

| 要什么 | 去哪找 | 怎么找 |
|---|---|---|
| 面板 id / 页签 / 字段 name / 按钮 id | 生成的 JSP | `src/main/webapp/WEB-INF/views/**/<页面名>.jsp` |
| 字段↔列名↔中文名、oneToMany 的 mappedBy | 实体模型 | `<模型目录>/**/实体/*.et`，按 `columnName=` grep |
| 子表真实表名、查询端点 | 生成的后端 | `generated/Abstract*.java`，看 `@OneToMany(targetEntity=...)` 和 `query12m/<name>` |

同名 `.custom.jsp` 是自定义 JS（改字段联动、必填校验、附加逻辑的入口），录数前值得扫一眼。

原因：靠肉眼在页面里找控件，往往要几十分钟，还会把"上一个项目的 id"照抄过来。

### 2. 认准 SPL5 前端骨架

关键结构与命名规律见 `references/spl5-frontend-map.md`。必须记住的几条：

- 面板 id 形如 `panel158703939`，页签锚点形如 `#tab180590082`，**只在当前项目里有效**，跨项目必须重查。
- 一对多内嵌列表的行内控件叫 `IE-<实体名>-<row_num>-<字段名>`（如 `IE-tbrzgtj-3-xmmc`）。
  `row_num` 是全局递增计数，**不是 1/2/3**，别用固定序号猜。
- 长文本字段是 `readonly` textarea，必须点开「输入 XXX」弹窗写。
  ⚠️ **弹窗的「确定」按钮不能用 `.ui-dialog` 选择器点**（它匹配不到那个按钮，点了没反应）。
  用 `query(kind="semantic", text="确定")` 拿带 frame 的 opaque ref 再 `click(ref)`。
- 提交走 `form.serializeArray()`，所以**只要控件 name/value 正确就能提交**，不需要额外同步行数据。

### 3. 选浏览器通道

内置 Browser（`mcp_browser`）是首选：它复用用户当前登录态。
本机日常 Chrome 若没开远程调试端口（`127.0.0.1:9222` 不可达）、Playwright MCP 是独立无登录态 profile，
两者都进不了需要登录的 SPL5 站点——不要在它们身上浪费轮次。

各 `query` kind 的实测行为与坑见 `references/browser-tool-tactics.md`。最常用的三条：

- `query(kind="editable")` 只列**当前激活页签**的控件 → 先切页签再查。
- `query(kind="dom")` 返回原始 HTML，是核对 input value / textarea 内容 / selected 的唯一可靠手段。
- `query(kind="text")` 取可见文本，**不反映表单控件的当前值**，不能用来判断"填上了没"。

### 4. 定位控件

- 稳定 id 用 `selector`（`#action166334845`、`a[href='#tab180590082']`、面板 id）。
- 按可见文本找元素用 `query(kind="semantic", text="...")`。
- 一次性拿当前页面的可点元素用 `inspect`。
- 一次只发一个 Browser 调用并等结果——这些调用共享页面状态，并发会互相污染。

### 5. 录入与保存

- **从父级单据页面点进去打开子单据，不要手工拼 URL。** SPL5 里服务端校验常常从
  URL query string 取参数（平台把它映射成 `queryString$<name>` 请求参数）。
  手工拼的 URL 少了这些参数，服务端会**跳过整段校验**（例如"至少录入1个资格条件"
  这类按项目类型分支的规则），造成"看着保存成功了、其实校验没跑"的假落库。
  父级页面用 `z.openWindow('.../子页面/cu/<id>?xxx=yyy&zzz=www')` 打开子页面，
  从那里点进去参数才是对的。
- 布尔字段是 radio（`name="<prop>" value="true|false"`）；码表下拉是 `select` + select2。
- 码表下拉的当前值在原始 HTML 里看不到 `selected` 属性，用 `inspect` 的 option `selected: true`
  或 `query(kind="semantic")` 看页面可见文本判断。
- 内嵌列表：点面板「新增」按钮加行 → 填控件 → 需要长文本就点开弹窗。
  ⚠️ 行内控件名里的 `<row>` 是**整页全局递增**的（多张表连续新增会拿到 3/4/5 这种连续号），
  先 `query(kind="dom", selector="input[name^='IE-xxx-']")` 看实际 row 号。
- 附件：上传控件常在 iframe 里，`upload_files` 的 ref 要取 iframe 内的 file input。
- 顺序按"先暂存拿到 id → 再上传附件 → 最后保存"：SPL5 的附件上传要求所属实体已有 id。
  ⚠️ **暂存只提交主表，保存才把子表一起提交**；暂存后刷新，子表会全空、评标办法会被重置。
- 点「保存」会弹确认框，点确认框的「是」。服务端校验不过会返回错误文案，**读出来再改**。
  ⚠️ 底部「暂存/保存/关闭」常是裸 `<button>`（无稳定 id），`query(kind="semantic", text="保存")`
  会误匹配到表单 label —— 用 `screenshot` 看像素位置 → `click(input={position:{x,y}})`。

### 6. 确认真的落库

页面回显为空 ≠ 没落库，页面看着对 ≠ 一定存对了。**以库为准**：

1. 从 `<项目>/src/main/resources/application.properties` 的 `spring.datasource.url` 拿到库地址与账号。
2. 用 `scripts/dbq.ps1` 直连查询（它会从 `target/*.jar` 里取出 mysql 驱动，用 JDK 21 单文件源码跑）。
3. 表名别按面板名猜：面板 `query12m/<name>` → `Abstract*.java` 的 `@OneToMany(targetEntity=...)` → 实体类 → 表名。
4. 关联列从 `mappedBy` 推：标段侧一对多都是 `mappedBy="ssxmbd"` → 子表 `ssxmbdId`。

完整命令与更多核对维度见 `references/verify-persistence.md`。

判断"真保存"的三个信号同时成立：父表 `deleted=0`；`sfzc`（是否暂存）不为真（`保存` 动作会置 false，`暂存` 不会）；
子表行数符合预期且 `deleted=0`。

### 7. 复核

重新加载页面，让服务端重新渲染一遍，逐项比对：页签切换后内嵌列表是否回显、码表下拉是否选中正确项、
布尔 radio 是否 checked、附件列表条数对不对。**再查一次库**，确认刷新没有把数据冲掉。

## Output contract

交付一份可复核的录入结论，包含：

- 落库对象的标识（单据 id、所属父级 id）
- 逐字段取值表 + 取值口径来源（来自父级单据 / 来自码表 / 来自用户指定）
- 内嵌列表与附件的行数、内容摘要
- **数据库核对结果**（查到的表名、行数、关键字段值）
- 遗留问题与平台侧已知缺陷（如保存后控制台报错但落库正常），明确区分"我的数据问题"和"平台 bug"

## Failure handling

- **保存后控制台报 `Cannot read properties of null (reading 'panelXXXXXXX')`**：页面独立打开、没有 opener
  时的前端回调缺陷，不代表保存失败。改用"重新加载 + 查库"判断，不要反复重存。
- **校验不通过**：服务端会返回具体文案（例如"至少录入1个资格条件""评标委员会人数为大于等于7的单数"）。
  按文案改，别猜。校验规则要从后端 service 里读，不要只看前端红字。
- **选码表下拉超时**：`select_option` 对 change 绑定后大面积重绘的下拉可能很慢；超时不等于失败，
  改用"切页签 → 重新取 ref → 再操作"，或直接 `query(kind="dom")` 核对最终值。
- **列表页面空白但库里明明有数据**：多半是查错了表或查错了关联列，回第 1 步用 `Abstract*.java` 重推。
- **查库连不上**：确认 `spring.datasource.url` 指向的是当前被测环境；本机无 mysql client 时走 `scripts/dbq.ps1`。
- **用户在场但页面无登录态**：让用户在同一 Browser 标签页登录，不要代填账号密码或验证码。
- **任务中途页面变成 502 或被重定向到 `/login`**：分两种情况处理，别一律当"功能坏了"。
  - 跳到 `/login` → **session 过期**，请用户重新登录后继续；不要试图自己登录或索要密码。
  - 502 → **多半是测试环境在发版重启**（不是崩溃）。**不要往"OOM/链路故障"方向猜**，
    也**不要下任何业务结论**（页面没渲染，"找不到控件"是假象）—— 等 1~2 分钟重试。
    需要确认时：`Invoke-WebRequest` 探站点 → SSH 到应用机 `curl 127.0.0.1:<应用端口>`
    看应用本身（返回 302/200 说明应用是好的，问题在网关到应用这一跳）。
    已提交的数据不会因此丢失，恢复后可接着做。
  详见 `references/browser-tool-tactics.md`。

## Examples

完整案例见 `references/cases.md`（案例 A 完整录入闭环 / B 排查"页面空但库里有数" / C 入口选择）。

Input: "用浏览器在汕尾测试环境给暗标测试项目录一条标段信息，保存后确认数据真的存进去了。"

Output 要点（完整版见 `spl5-bid-section-entry` skill）：

1. grep 生成的 `jsgczbxmbdbjcly.jsp` → 拿到 5 个页签、4 个评审面板 id、各「新增」按钮 id、字段 name。
2. 读父级交易申请页 → 取总投资 100 万、标准工期 300 天、交易类型 A01。
3. 按 A01 + 评定分离 的校验口径定值：评标办法 06 定性评审、评标委员会 5 人、定标办法单轮票决法、定标委员会 7 人。
4. 暂存 → 上传招标文件 → 保存（确认框点「是」）。
5. 查库：`jsgczbxmbd` 1 行（sfab=1、sfzc 非暂存）、`jsgczbtbrzgtj`/`jsgczbtbrfhxsc`/`jsgczbxmjsyq`/`jsgczbxmswyq` 各 1 行、`jsgczbxmbdfj` 1 条 category='zbwj'。
6. 重新加载页面，确认四张表与附件列表都能从服务端回显。

## Windows (win32) platform notes

- `scripts/dbq.ps1` 是 PowerShell 脚本。文件已带 UTF-8 BOM，Windows PowerShell 5.1 与
  PowerShell 7 都能直接跑：`powershell -ExecutionPolicy Bypass -File scripts/dbq.ps1 -Sql "SELECT ..."`。
  脚本内部已设置控制台 UTF-8 与 `JAVA_TOOL_OPTIONS`，中文结果不会乱码。
- 需要 JDK 21（单文件源码免编译）：`D:\app\java\jdk-21\bin\java.exe`，脚本会自动探测。
- 非 Windows 环境把 `Expand-Archive` 换成 `unzip`，其余步骤一致。

