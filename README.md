# spl5-browser-test

用内置浏览器在 **SPL5（生产线5）公共资源交易平台**上定位控件、录入测试数据、确认落库。

An Agent Skill for locating SPL5 UI controls, entering test data through the built-in
browser, and verifying that the data actually landed in the database.

SPL5 页面是**代码生成**出来的：控件 id、字段 name、面板结构写死在生成的 JSP 里，
字段↔列名写死在 `.et` 模型里，关联关系写死在 `generated/Abstract*.java` 里。
所以**别在页面里盲找控件，先 grep 仓库** —— 几分钟就能拿到全部稳定 id。

---

## 它解决什么问题

在 SPL5 上录一次数据，要过的坎不是"点哪里"，而是：

- **控件 id 会变**：换项目、重新生成模型，全部 id 都变。照抄上一个项目的 id 必然翻车
- **表名不等于面板名**：面板叫「投标总价量化表」，真实表叫 `jsgczbxmtbzjlhb`
- **"保存成功"不等于"落库"**：URL 少一个 query 参数，服务端会**整段跳过校验**
- **页面显示的值是假的**：`.numberFormat()` 字段写的是 DOM property，
  `query(kind="dom")` 读的是 HTML 属性，读出来常常是空
- **`bit(1)` 列读不出来**：套进 `CONCAT` 就变成控制字节，打印成空白 —— 看着像"没值"，其实是 1

这份 skill 把每一条都写成了可执行的规则，并附带一个**不需要装 mysql client** 的查库脚本。

---

## 安装

把整个 `spl5-browser-test/` 放进你的 agent 的 skills 目录：

| Agent | 路径 |
|---|---|
| MiniMax Code / Mavis | `~/.minimax/agents/<agent-name>/skills/spl5-browser-test/` |
| Claude Code | `~/.claude/skills/spl5-browser-test/` |

其他客户端的 skills 目录位置各不相同，参见各自文档。

无第三方依赖。`scripts/dbq.ps1` 需要 **JDK 21**（单文件源码免编译），
脚本会自动探测；本机没有 mysql client 也能查库。

---

## 用法

skill 由 agent 按 `SKILL.md` 里的 Procedure 自动执行。典型触发语：

> "用浏览器在汕尾测试环境给暗标测试项目录一条标段信息，保存后确认数据真的存进去了。"

### 查库脚本（独立可用）

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dbq.ps1 `
  -ProjectRoot 'D:\path\to\your\spl5-project' `
  -Sql "SELECT COUNT(*) FROM your_table WHERE id='...'"
```

脚本会：从 `target\*.jar` 里取出 mysql 驱动 → 用 JDK 21 跑单文件源码 → 打印结果。
连接信息从 `<ProjectRoot>/src/main/resources/application.properties` 的 `spring.datasource.*` 读取，
**不需要另外配置**。

---

## 内容

| 文件 | 内容 |
|---|---|
| [`SKILL.md`](SKILL.md) | 主流程：读模型 → 认页面骨架 → 定位控件 → 录入 → 查库 → 复核 |
| [`references/spl5-frontend-map.md`](references/spl5-frontend-map.md) | SPL5 前端骨架：页签/面板/内嵌列表/字段的命名规律 |
| [`references/browser-tool-tactics.md`](references/browser-tool-tactics.md) | 浏览器工具的具体手法：跨 frame 弹窗、numberFormat、坐标点按钮、502 判别 |
| [`references/verify-persistence.md`](references/verify-persistence.md) | 落库核对：表名推导、"真保存"的三个信号、逐字段比对 |
| [`references/cases.md`](references/cases.md) | 真实案例：完整录入闭环、"页面空但库里有数"、入口选择 |
| [`scripts/dbq.ps1`](scripts/dbq.ps1) | 免 mysql client 的查库脚本 |

---

## 几个关键结论（详情见 references）

| 坑 | 正确做法 |
|---|---|
| 找不到控件 | grep 生成的 JSP，别用 `inspect` 硬找 |
| `fill` 后金额变成 `10000001000000` | click → Ctrl+A → Backspace → type → 点别处 blur |
| 读金额读出来是空的 | **只有 `screenshot` 可靠**（DOM/editable 读的是 HTML 属性） |
| 弹窗「确定」点了没反应 | `query(kind="semantic", text="确定")` 拿 ref 再 `click` |
| 页面 502 | **多半是测试环境在发版重启**（不是崩溃）—— 等 1~2 分钟重试，别下业务结论 |
| 跳到 `/login` | session 过期，请用户重新登录，不要代填凭据 |

---

## License

MIT — 见 [LICENSE](LICENSE)。
