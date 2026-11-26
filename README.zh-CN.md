# 一键优化全家桶 · OneClickOptimizer

**一个模块化、可追溯的 Windows 软件配置工具。** [English](README.md)

当前版本：`0.1.0-alpha.1`（开发预览）。目前仅提供 Positron 模块；不把未来规划当作已实现功能。

## 使用方法

完整解压后双击 `启动全家桶.bat`，选择 Positron → 仅检查，确认优化内容后再选择优化。保存工作后自行重启软件。也可直接运行 `modules/positron/一键优化.bat`。适用目标为 Windows 10/11、Windows PowerShell 5.1；陌生电脑仍需兼容性验收。详细见 [Positron 说明](modules/positron/使用说明.md)。

不需要管理员权限；不联网、不关闭安全软件、不安装第三方程序、不强制停止用户进程。实际安装路径与下载安装包位置不同：按进程、注册表、PATH、快捷方式、常见路径及重定向 Downloads 查找，并提供手动定位。支持显式配置路径，不能保证发现任意自定义路径或不在运行的自定义 Profile。

原始设置有变化才写入，备份和回读验证；不收集账号密码、Token，不将个人配置提交到仓库。关闭 R 诊断是使用偏好，切换 base 安装器并非实测速率结论。默认七项目标以 PDF 的工作流为依据，非所有人的最佳方案。

## 工程规范

- [模块接口](docs/MODULE-CONTRACT.md) · [路线图](docs/ROADMAP.md) · [验证状态](docs/VALIDATION.md)
- [AI 维护规范](AGENTS.md) · [变更记录](CHANGELOG.md) · [贡献说明](CONTRIBUTING.md)
- 主分支保留已验收模块；新软件通过 feature 分支开发，然后合并至 `modules/<id>/`。

采用 MIT 许可证，项目与各软件官方无隶属关系。
