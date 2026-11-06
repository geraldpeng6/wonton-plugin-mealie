# 云吞插件：Mealie

开发流程见[插件开发指南](https://github.com/geraldpeng6/wonton-docs/blob/main/develop.md)。

Mealie（[docs.mealie.io](https://docs.mealie.io)，AGPL-3.0）是自托管的菜谱库：从网址导入菜谱或手动建，按食材和标签找菜，
排一周菜单、生成购物清单，数据和图片都在自己家里。这个插件把它装进云吞：网页经核心网关打开，登录走核心的身份提供方，
主人的账号就是 Mealie 的管理员；主人在云吞里没配邮箱时插件装不上——Mealie 登录把邮箱声明列为必需。

插件用上游官方镜像 `ghcr.io/mealie-recipes/mealie`，按摘要固定。数据（SQLite、图片）在插件自己的数据目录里，
不需要额外的数据库和缓存服务。

## 图标来源与许可

`icon.png` 取自 Mealie v3.30.0 的官方 PNG（frontend/public/icons/android-chrome-maskable-512x512.png），未用图片模型生成；来源、版权、处理方式、上游 AGPL-3.0 全文和商标说明见 [NOTICE](NOTICE)。

该标志为 Mealie 项目及其权利人的商标，仅用于识别本插件所集成的应用；本插件不代表 Mealie 官方，
也不表示获得 Mealie 的合作、认可或背书。

## 先跑起来

```bash
scripts/dev.sh up
scripts/dev.sh install
```

`up` 在本机起一套云吞并打印它的地址，用 `scripts/dev.sh token` 输出的用户令牌登录；`install` 列出插件要的权限，确认后
装上并打印插件网页的地址，打开就直接以云吞身份进 Mealie，不用再登录。

## 仓库里有什么

| 路径 | 内容 |
| --- | --- |
| `docker-compose.yml` | 插件本身：compose 加上 `x-wonton` 清单 |
| `icon.png` | 清单引用的文件：图标（来源和许可见 `NOTICE`） |
| `screenshots/` | 商店详情页里的截图 |
| `scripts/check.sh` | 检查插件包，规则和安装时一样 |
| `scripts/dev.sh` | 开发环境：起一套云吞，装、重装、卸载插件，看日志 |
| `scripts/smoke-probes.sh` | `scripts/dev.sh smoke` 对这个插件逐项的探测 |
| `scripts/publish.sh` | 发布一个版本：打 tag、推送 |
| `AGENTS.md` | 给人和 AI 编程代理的规则 |
| `LICENSE`、`NOTICE` | 插件许可证、上游 AGPL-3.0 许可证和商标声明 |
