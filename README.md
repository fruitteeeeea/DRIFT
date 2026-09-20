# DRIFT 漂流小岛

一个依赖浏览器 WebGL 2 的单页互动海岛，并带有 Supabase 公共留言板。

## Supabase

1. 在 Supabase SQL Editor 中执行 [`supabase.sql`](./supabase.sql)。
2. 将项目的 publishable key 填入 [`config.js`](./config.js)。
3. 绝不要在前端放置 secret key 或 legacy `service_role` key。

将 `config.js` 中的 `guestbookEnabled` 设为 `false` 可同步隐藏留言输入界面；数据库写入权限仍应通过 `REVOKE INSERT` 单独关闭。

留言表仅向访客开放读取可见留言和创建 1–120 字留言；新留言默认公开显示，更新、删除和可见性管理不对公网开放。

## GitHub Pages

推送到 `main` 后，GitHub Actions 会自动部署仓库根目录。工作流位于 `.github/workflows/pages.yml`。
