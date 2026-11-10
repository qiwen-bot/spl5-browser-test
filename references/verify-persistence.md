# 核对"浏览器录入是否真的落库"

页面回显为空 ≠ 没落库；页面看着对 ≠ 一定存对了。**以库为准**——这是本文件存在的唯一理由。

## 什么时候必须查库

- 用户说"录入并保存/落库"→ 必须查。
- 页面某个列表显示为空、但你确信刚填过 → 必须查（可能查错了表，也可能真没存上）。
- 改完长文本字段后 → 查一次，确认没有把重复内容写进库。

## 步骤

### 1. 拿到连接信息

从**被测项目**的 `src/main/resources/application.properties` 读：

```
spring.datasource.url=...      # 确认它指向你正在测的那个环境
spring.datasource.username=...
spring.datasource.password=...
```

汕尾实测：测试环境 `test.swggzyjy.rongzhiwang.com` 用的是
`jdbc:mysql://192.168.40.71:3307/swggzyjy`（账号密码见同一文件）。
不同项目/环境地址不同，**不要照抄**。

### 2. 直连查询

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dbq.ps1 -ProjectRoot "<项目根>" `
  -Sql "SELECT id,bdmc FROM jsgczbxmbd WHERE id='<id>'"
```

脚本做的事：从 `target\*.jar` 里取出 `BOOT-INF/lib/mysql-connector-java-*.jar`，
再用 JDK 21 的单文件源码免编译能力跑内嵌查询器。无需 mysql client、无需 pip。
脚本带 UTF-8 BOM，Windows PowerShell 5.1 与 PowerShell 7 都能直接跑，中文结果不乱码。

可选参数：`-JarPath`、`-DbUrl`、`-DbUser`、`-DbPass`、`-MaxRows`、`-ProjectRoot`。

### 2.1 先确认线上真实表结构

仓库里的 `init.sql` 可能**早于当前部署版本**（例如缺后来加的列、缺新表）。
拿它拼 SQL 容易查错对象。查库前先确认：

```sql
SELECT table_name, GROUP_CONCAT(column_name ORDER BY ordinal_position) cols
FROM information_schema.columns
WHERE table_schema=DATABASE() AND table_name LIKE 'jsgczbxm%'
GROUP BY table_name
```

### 3. 反查真实表名（关键，别按面板名猜）

```
面板 query12m/<name>
   → generated/Abstract*.java 的 @OneToMany(targetEntity = AbstractXxx.class)
   → 实体类 AbstractXxx 的 @Table(name=...) 或同名 .et 的 tableName
```

汕尾标段编辑页的实例（`jsgczbxmbdbjcly`）：

| 面板 | query12m 路径 | 真实表 | 关键列 |
|---|---|---|---|
| 投标人资格评审项目 | `query12m/tbrzgtj` | `jsgczbtbrzgtj` | xh, xmmc, nryq |
| 形式评审、响应性评审项目 | `query12m/fhxsc` | `jsgczbtbrfhxsc` | xh, xmmc, nryq |
| 技术评审项目 | `query12m/jsyqb` | **`jsgczbxmjsyq`** | xh, psxmmc, pssm |
| 商务评审项目 | `query12m/swyqb` | **`jsgczbxmswyq`** | xh, psxmmc, pssm |
| 招标文件 | `query12m/zbwj` | `jsgczbxmbdfj` | ownerId=标段id, category='zbwj' |

`jsgczbxmtbjsyqb` / `jsgczbxmtbswyqb` 是**另一组实体**（技术要求表 / 商务要求表），
跟上面两个面板无关——查错表就会得出"没落库"的假结论（本 skill 的作者就踩过这个坑）。

### 4. 反查关联列

子表里的 `ssxmbdId` 来自父表侧的 `@OneToMany(mappedBy = "ssxmbd")`。
子表往往还有第二个 FK（如 `ssgzmxId`），**查询不走它**，别拿它当过滤条件。

框架侧查询逻辑（`zsoft-web` 的 `AbstractFormCtrller.execOneToManyQuery`）：
`where mappedBy = ownerId OR id IN (unassociated)`，ownerId 取表单的 `input[name=".id"]`。

### 5. 判定"真保存"

三个信号同时成立才算存上了：

1. 父表 `deleted = 0`；
2. `sfzc`（是否暂存）不为真 —— `保存`(bc) 动作会把它置 false，`暂存`(zc) 不会；
3. 子表行数符合预期且 `deleted = 0`，没有多出来的历史行。

⚠️ **`sfab` / `sfzc` / `deleted` 常是 `bit(1)` 列**。直接 `SELECT sfab` 拿到的是 "1"/"0"，
但一旦套进 `CONCAT`/`IFNULL`，MySQL 会把它当二进制串，控制字节打印出来是**空白**，
看起来像"没值"。**这三个信号必须 `CAST(sfab AS UNSIGNED)` 读**，否则会把"已保存"误判成"没存"。
（`dbq.ps1` 已加兜底：遇到不可见控制字符会打成 `0x..` 十六进制，但 SQL 里显式 CAST 更清楚。）

### 5.1 「暂存」与「保存」落库范围不同（2026-11-10 实测）

| 动作 | 父表 | 一对多子表 | `sfzc` |
|---|---|---|---|
| **暂存** | 落库 | **不落库** | 1 |
| **保存** | 落库 | **一并落库** | 0 |

暂存只提交主表单，所以：
- 暂存后刷新页面，**所有内嵌列表都是空的**（这不是 bug）；
- 暂存后刷新，**下拉/单选等子表单字段也可能被重置**（如评标办法回到 `--请选择--`）。

**结论**：要验证子表是否落库，必须走「保存」并确认框点「是」；只暂存就查子表，
得到的 0 行是预期结果，不能据此判断"没保存成功"。
另外，子表单数据若存在 `jsgczbxmpfff` 这类**独立的关联表**里，父表刷新后查不到它，
要 `JOIN` 父表的 FK 列（如 `pfffId`）去查。

一条 SQL 同时看四张子表行数：

```sql
SELECT (SELECT COUNT(*) FROM jsgczbtbrzgtj WHERE ssxmbdId='<标段id>') tbrzgtj,
       (SELECT COUNT(*) FROM jsgczbtbrfhxsc WHERE ssxmbdId='<标段id>') fhxsc,
       (SELECT COUNT(*) FROM jsgczbxmjsyq  WHERE ssxmbdId='<标段id>') jsyqb,
       (SELECT COUNT(*) FROM jsgczbxmswyq  WHERE ssxmbdId='<标段id>') swyqb,
       (SELECT COUNT(*) FROM jsgczbxmbdfj  WHERE ownerId='<标段id>' AND category='zbwj') zbwj
```

## 核对完还要回页面复核

重新加载页面让服务端重渲染一遍：内嵌列表有没有行、码表下拉选中没有、radio checked 没有、
附件条数对不对。**再查一次库**，确认刷新没有把数据冲掉。
