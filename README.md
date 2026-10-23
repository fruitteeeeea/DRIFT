# DRIFT 漂流小岛

一个依赖浏览器 WebGL 2 的单页互动海岛，并带有 Supabase 公共留言板。

## Supabase

1. 在 Supabase SQL Editor 中执行 [`supabase.sql`](./supabase.sql)。
2. 将项目的 publishable key 填入 [`config.js`](./config.js)。
3. 绝不要在前端放置 secret key 或 legacy `service_role` key。

将 `config.js` 中的 `guestbookEnabled` 设为 `false` 可同步隐藏留言输入界面；数据库写入仍应通过下述服务端停写开关单独关闭。

留言表仅向访客开放读取可见留言和创建 1–120 字留言；新留言默认公开显示，更新、删除和可见性管理不对公网开放。

## GitHub Pages

推送到 `main` 后，GitHub Actions 会自动部署仓库根目录。工作流位于 `.github/workflows/pages.yml`。

## 服务端防刷屏（必须部署数据库修改）

浏览器仍直接 POST `/rest/v1/drift_messages`，读取、展示和即时公开不变。
`BEFORE INSERT` 触发器覆盖 anon、authenticated、批量插入以及绕过网页的请求。
隐藏字段和本地 30 秒冷却只用于体验，不是安全边界。

默认**全站**滚动配额为每分钟 10 条、每小时 100 条；10 分钟内相同内容
（忽略大小写及空白）不可重复。数据库拒绝空白、超长、控制字符与常见不可见/方向控制字符，
允许正常换行和表情。私有状态行加锁，将检查和配额占用放进同一事务；多行提交任何一行失败会整批回滚。
历史最多保留一小时的 100 条摘要和时间，不保存 IP，不受删除/隐藏留言影响。

这是匿名小站的最小总量保护：攻击者可消耗共享配额导致正常访客暂时不能留言，
也不能阻止低频且内容各异的垃圾信息或 HTTP 请求洪泛。不能把客户端 IP、自定义 header
当作可信身份。流量增长时应关闭公开 INSERT，迁移到可信网关/Edge Function，
再使用可信来源 IP、持久化限频和服务端验证码校验；不能只加前端验证码。

### 部署顺序

1. 先备份数据库。在测试项目由 `postgres` 执行现有表升级脚本
   [`supabase/migrations/202610230001_guestbook_guard.sql`](./supabase/migrations/202610230001_guestbook_guard.sql)。
   新项目执行完整 `supabase.sql` 即可。两者包含同一保护定义，可重复执行，保留配额和停写状态。
2. 在目标项目 SQL Editor 以管理员身份执行同一迁移，再发布网页。
   无需新增 key、secret 或前端配置；仅部署 GitHub Pages **不会启用数据库防护**。
3. 按下述方法验证，检查 Supabase API 日志中的 400/429/503。
   不要对线上站点进行压力测试。默认阈值可在函数内修改后重新执行迁移，并同步修改完整脚本。

### 验证与测试

`node --test tests/guestbook-ui.test.cjs` 检查成功、重复、限频、停写提示及失败保留输入。
在一次性空 PostgreSQL 数据库运行：

```sh
psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/guestbook.sql
```

SQL 测试建立 anon/authenticated 角色，覆盖正常即时公开、重复、非法内容、直接数据库插入、
分钟/小时配额、换角色、删除后不能绕过、停写、过期恢复和私有状态权限。
CI 使用 PostgreSQL 17 运行测试，并通过 20 个独立连接验证并发配额。不要在生产数据库执行此测试脚本。

在测试 Supabase 项目用 curl 绕过前端（URL 和 publishable key 取该测试项目）：

```sh
curl -i "$SUPABASE_URL/rest/v1/drift_messages" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" -H 'Content-Type: application/json' \
  -d '{"content":"部署验证留言"}'
```

首次应为 201 且 GET 可见；再次相同内容应为 429，错误消息 `duplicate_message`。
一分钟内提交第 11 条不同留言应为 429 `guestbook_rate_limited`。
同时从多个终端提交超过 10 条不同留言，确认一分钟总成功数不超过 10；并验证批量请求不能突破配额。
等待窗口过期后可恢复。新页面应展示明确提示，失败时保留便签。

### 滥用处置

仅在管理员 SQL Editor 中操作：

```sql
-- 立即停止所有新留言（现有留言仍可读；直接 API 同样被阻止）。
update drift_private.guestbook_guard set enabled = false where singleton;
-- 按实际 ID 隐藏违规留言，不要删除配额状态。
update public.drift_messages set is_visible = false where id = '违规留言的 UUID';
-- 排查并处理后恢复。
update drift_private.guestbook_guard set enabled = true where singleton;
```

停写返回 503 `guestbook_paused`。私有 schema 不应加入 Supabase exposed schemas。
不要授予访客私有表权限或函数权限。紧急时还可 `REVOKE INSERT (content) ON
public.drift_messages FROM anon, authenticated`；恢复需显式重新授权。
只回退网页无需撤销触发器；不要为了回退 UI 而移除服务端保护。
