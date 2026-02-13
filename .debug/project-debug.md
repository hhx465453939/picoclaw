# 项目全局 Debug 记录

## 元信息
- 模块名称: project-global
- 创建时间: 2026-02-13
- 最后更新: 2026-02-13
- 相关文件: 整个项目
- 依赖模块: 待补充
- 用户说明书路径（涉及前端功能时）: 待补充
- 开发/部署文档路径（涉及后端或环境时）: 待补充

## 运行上下文与测试规则（首次确认后填写，后续优先读取此处，不再反复询问）
- 运行环境: NAS-Samba+SSH 或远程
- SSH 方式（若远程）: ssh home_nas
- 远程项目路径（若远程）: /home/damncheater/Development/picoclaw
- 验证/Checkfix 执行方式: 在本地终端执行，例如：
  - ssh home_nas "cd /home/damncheater/Development/picoclaw && <调试或检查命令>"

## 上下文关系网络
- 文件结构: 待根据具体模块补充
- 函数调用链: 待根据具体模块补充
- 变量依赖图: 待根据具体模块补充
- 数据流向: 待根据具体模块补充

## Debug 历史
- 2026-02-13 记录项目运行环境与测试规则：通过 ssh home_nas 登录 NAS，在远程 Ubuntu 环境下进入 /home/damncheater/Development/picoclaw 执行所有调试与 Checkfix 命令。
- 2026-02-13 修复 Docker 构建 Go 模块网络问题：在 Dockerfile 的 builder 阶段设置 GOPROXY=https://goproxy.cn,direct，重新执行 `ssh home_nas "cd /home/damncheater/Development/picoclaw && docker compose --profile gateway build"`，构建成功。
- 2026-02-13 部署与启动 Gateway：在 NAS 上执行 `ssh home_nas "cd /home/damncheater/Development/picoclaw && docker compose --profile gateway up -d"`，容器 picoclaw-gateway 成功启动并运行（日志显示 Agent 初始化完成、Cron/Heartbeat 服务正常，当前无启用的外部聊天渠道）。

## 待追踪问题
- 根据后续具体模块调试记录补充。

## 技术债务记录
- 待补充。

## 架构决策记录（可选）
- 采用 NAS-Samba+SSH 开发形态：本地 IDE 编辑代码，所有实际运行与检查均在远程 Ubuntu 上执行。

