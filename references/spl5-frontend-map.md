# SPL5 前端骨架速查

面向"要在 SPL5 页面里定位控件并录数"的模型。所有 id 形态来自汕尾建设工程项目实测，
**具体 id 必须去目标项目重新 grep**，只把这里当结构规律用。

## 文档骨架

生成的 JSP 形如：

```html
<body FormPage class="form-page">
  <form id="mainForm">
    <input name=".id" value="${jsgczbxmbd.id}" type="hidden" />
    <input name="_customData" id="_customData" value="${_customData}" type="hidden" />
    ...所有面板都在这个 form 内...
  </form>
</body>
```

- `input[name=".id"]` 是一对多面板的 ownerId 来源（`oneToMany-ownerId=".id"`）。
  页面上的 `query12m/<name>` 请求就带它做查询条件。
- 提交由 `jquery.z.submitButton.js` 的 `fetchFormData` → `form.serializeArray()` 完成。
  **只要控件的 name 和 value 正确，就一定会被提交**；不存在"必须同步行数据"的额外步骤。

## 页签（TabPanel）

```html
<div id="panel179765040" TabPanel class="widget tab-panel">
  <ul class="nav nav-tabs">
    <li class="active noclose"><a href="#tab179798141" data-toggle="tab">标段信息</a></li>
    <li class="noclose"><a href="#tab180590082" data-toggle="tab">资格评审</a></li>
  </ul>
  <div class="tab-content">
    <div class="tab-pane" id="tab179798141"> <div id="panel180941525" FormPanel> ... </div> </div>
    <div class="tab-pane" id="tab180590082"> <div id="panel158703939" OneToManyListPanel> ... </div> </div>
  </div>
</div>
```

- 切换页签：`click(selector="a[href='#tab180590082']")`。
- 页签是 `display:none` 切换，`query(kind="text")` 对隐藏页签里的内容可能取不到，
  `query(kind="editable")` 只列**当前激活页签**的控件。

## 主表字段

| 控件类型 | 渲染结果 | 录入方式 |
|---|---|---|
| 文本 | `<input name="bdmc" value="...">` | `fill` |
| 长文本 | `<textarea name="jsnrhgm" class="lg2 longtext-area ">` | `fill`（非 readonly 的主表长文本可直接填） |
| 数字 | `<input name="bzgqrlt" value="300">` | `fill`；带 `numberFormat` 时回显会带千分位 |
| 布尔 | `<z:boolean>` → `<input type="radio" name="sfab" value="true" checked>是` | `check` 对应 radio |
| 码表 | `<z:codetext>` → `<select name="zgscfsCode">` + select2 | `select_option`（重绘多的下拉会慢） |

- 布尔 radio 的 `value` 是 `true`/`false`，不是 `1`/`0`。
- 码表下拉的 `selected` 状态**不体现在原始 HTML 属性上**（select2 接管后由 JS 设置），
  判断当前值要看 `inspect` 里 combobox 的 option `selected: true`，或页面可见文本。

## 一对多内嵌列表（OneToManyListPanel）

```html
<div id="panel158703939" OneToManyListPanel
     url=".../jsgczbxmbdbjcly/query12m/tbrzgtj" oneToMany-ownerId=".id">
  <input type="hidden" name="o#" value="xh@asc" />
  <input type="hidden" name="custom$tbrzgtj" />
  <input type="hidden" name="oneToMany$unassociated$tbrzgtj" unassociated />
  <input type="hidden" name="oneToMany$deleted$tbrzgtj" temp-deleted />
  <button id="action166334845" onclick="panel158703939.lpImpl.addIERow();">新增</button>
  <table id="panel158703939Table" inline-editing> ... </table>
</div>
```

### 行内控件命名

```
IE-<实体名>-<row_num>-<字段名>      例：IE-tbrzgtj-3-xmmc
IE-<实体名>-<row_num>-id            例：IE-tbrzgtj-3-id（隐藏列，存已落库行的主键）
```

- `row_num` 来自 `$.listPanelImplementor.loopRowNum`（全局递增），**不是 1/2/3**。
  同一个页面上不同面板的 row_num 会继续累加，所以 `tbrzgtj` 可能是 3 而 `fhxsc` 是 4。
- 隐藏 id 列的 input 带 `_id` 属性；保存成功后服务端在响应里返回 `IE$<实体名>` 属性
  （row_num → 新 id 的映射），前端 `handleInlineEditingPersistedIds` 回填到行数据。
  这说明服务端认得这些行，所以**行的存在本身不需要额外同步**。

### 新增 / 删除行

- 新增：`click(selector="#action166334845")`（或面板 JSP 里的 `onclick` 属性）。
- 删除：行内 `<a onclick="panelXXX.lpImpl.deleteRow(this)">删除</a>`。

### 长文本字段

```js
var tag = $( '<textarea name="IE-tbrzgtj-{{entity.row_num}}-nryq" readonly class="ie-textarea">{{data}}</textarea>' );
tag.longTextInputDialog();
```

- readonly textarea 直接 `fill` 会失败（ACTION_EFFECT_MISMATCH）。
- 正确做法：`click` 该 textarea → 弹出「输入 内容要求」/「输入 评审说明」对话框 →
  在弹窗内的 textarea 写入 → 点「确定」。
- **弹窗会预填当前值再整体覆盖**（长文本对话框 `jquery.z.adhoc.js`）。所以坑不是"弹窗自动追加"，
  而是**弹窗里已经带着旧内容**——你在它后面接着写，提交出去就是两份。
  写的时候先全选清空，或写完用 `query(kind="dom")` 看原始 HTML 确认 textarea 是单份。
- 判定"库里是干净的"要查库，不能只看 DOM。

### 渲染期的 `{{data}}`

`createdCell` 里 `value="{{data}}"` 是**渲染期单向输出**，之后改 DOM 不会回写行数据；
但提交取的是 DOM 本身（`serializeArray`），所以"填对 DOM → 提交就带得上"成立。

## URL query string 参与服务端校验

SPL5 的子单据常把"项目类型/标段类型/交易方式"这类参数放在打开子页面的 URL query string 里，
平台再把 query string 映射成 `queryString$<name>` 形式的请求参数给后端：

```js
// 父级页面的 custom.jsp
z.openWindow('${contextPath}/.../jsgczbxmbdbjcly/cu/' + id
             + '?zbxmlx=' + zbxmlx + '&zblx=' + zblx + '&dbms=' + dbms);
```

后端 `doValidate` 里就是 `request.getParameter("zbxmlx")` / `request.getParameter("queryString$dbms")`。

**后果**：手工拼一个没有 query string 的 URL 打开子页面，服务端拿到的项目类型是 null，
按项目类型分支的那段校验会被整段跳过 → 数据"保存成功"但没经过应有校验。
**从父级页面点进去，别手拼 URL。**

## 页面标签 vs 实体 nameCN

同一个字段，JSP 上的**界面标签**和实体模型里的 `nameCN` 可能不是一回事
（例如列 `jsnrhgm` 在模型里叫"建设内容和规模"，在页面标签里叫"招标内容"）。
- 填表、校验报错、以"至少填写N个字"为准的规则 → **以 JSP 标签和后端报错文案为准**。
- 写 SQL、拼参数名 → 用**列名/属性名**。
- 判断字段必填性 → 看后端 `doValidate` 和 service，不看模型 `required`（模型的 required 常常和实际校验不一致）。

## 校验代码的两个位置

- **控制器**（`web/.../XxxCtrller.java` 的 `doValidate`）：与本单据强相关的硬校验
  （金额大小关系、附件份数、字数下限、字段长度上限）。
- **service**（`custom/service/.../XxxService.java` 的 `validateNormal` / `validateFJSZ` 等）：
  按项目类型分支的通用规则（评审列表条数、委员会人数、评标办法分支要求）。

两个都要读，只读一个会漏判。另注意 `CommonUtil.isStringSentencedEmpty(x)`
的语义是反的：**内容非空才返回 true**，所以 `if (isStringSentencedEmpty(x)) { 报错"必须填写" }`
实际拦的是"内容为空"。

## 按钮与保存流

- 底部动作按钮：暂存 / 保存 / 关闭，id 形如 `#action09bje8ifhkgf`（暂存）、`#action0a0259ef61c3`（保存）。
- 点「保存」弹确认框（「是否保存项目标段？」），确认框的肯定按钮是 `button.confirm`。
- 保存走 `actionBc`（保存）或 `actionZc`（暂存），对应后端 `Abstract*.java` 里的 `ACTION_BC` / `ACTION_ZC`。
- 校验不过时后端返回具体错误文案，读文案改值，别猜。

## 附件

- 面板里的上传控件常在 **iframe** 内（`upload_files` 的 ref 取 iframe 内的 `input[type=file]`）。
- SPL5 附件上传要求所属实体已有 id，所以顺序是：暂存 → 上传 → 保存。
- 附件表按 `category` 区分用途（招标文件 `zbwj`、标段附件 `bdfj`、开标记录 `kbjlb` …），
  用 `ownerId` 关联到主表 id。
- 部分平台页面把「生成招标文件」按钮用 `c:if false` 隐藏，此时只能手动上传附件。
