# AGENTS.md

多机 NixOS / Home Manager 配置仓库，三个部署目标（`oci` / `asahi` / `XueMacBook-Pro`），全部由 `flake.nix` 声明式管理。

**操作手册是 `README.md`**：加包、应用变更、升级、回滚、换机还原的步骤都在里面，动手前先读对应小节。本文件只记不读就一定会踩的约定，其余一律查 README，不在此重复。

## 版本控制：用 jj，不用 git

这是 jj + git **colocated** 仓库（`.jj/` 与 `.git/` 并存）。**所有改动走 jj，git 只读。**

- 看历史用 `git log` 或 `jj log` 都行；**不要** `git pull` / `git checkout` / `git reset`。
- git HEAD 永远是 detached——那是 colocated 的正常状态，不是故障，别去"修"。
- 提交：`jj new <parent> -m "<scope>: <描述>"`；改已有提交用 `jj describe` / `jj squash` / `jj split`。
- 提交信息带 **scope 前缀**（`asahi:` `oci:` `flake:` `security:` `restic:` `home:` `README:`），主体一句中文说清改了什么、为什么。

## 新文件先让 jj 快照到

flake 求值读的是 git 的跟踪状态：**刚创建、还没被 jj 快照过的新文件对 nix 不可见**，会报 `error: Path '...' is not tracked by Git.`。跑任意一条 jj 指令（`jj st` 即可）触发自动快照——jj 会把新文件以 intent-to-add 登记进 git 索引，nix 即认作已跟踪并读到工作树的完整内容，无需先 commit。

## 改动规范

- `.nix` 一律 `nixfmt` 格式化（仓库统一格式化过，别破坏）。
- 行为变了就把 `README.md` 对应小节一起更新。

## 注释写 why

配置里每处非显而易见的设置都要写**为什么**：上游 bug 链接、issue 号、commit hash、权衡。what 代码自会说；值得写的是查不到的那个原因。

## 绕开上游 bug 时留 TODO revisit

任何绕开上游 bug 的补丁、或跟着上游版本会失效的假设，原地留统一格式：

```nix
# TODO revisit: <什么条件下回来看>
#   check: <怎么验证>
#   then:  <验证后怎么办>
#   last:  <YYYY-MM, 上次检查的版本与结论>
```

升级后的复查流程见 README「复查清单（TODO）」。
