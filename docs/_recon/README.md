# `_recon/` —— 侦察与实验证据附录

本目录是 [`../xtb-架构与GFN2独立编译可行性.md`](../xtb-架构与GFN2独立编译可行性.md) 的**证据来源**。

主文档中所有标注「实测」的结论，其原始输出都在此目录。所有构建/链接实验均在 `/tmp` 下进行，**仓库工作树未被修改**（`git status` 仅显示新增的 `docs/`）。

| 文件 | 内容 | 产生方式 |
|---|---|---|
| `01-build-system.md` | CMake/Meson 目标图、外部依赖矩阵、构建选项、运行时数据路径与安装规则、CI 矩阵 | 只读侦察（scout） |
| `02-module-map.md` | `src/` 全目录职责、顶层文件功能聚类、模块 fan-in 排序、目录间 use 环、全局状态分析、依赖分层建议 | 只读侦察（scout） |
| `03-gfn2-call-chain.md` | `primary.f90` → GFN2 Hamiltonian 完整 hop 序列、方法分派、各能量项 in-tree/外部判定、SCF/SCC 两层结构、最小文件清单 | 只读侦察（scout） |
| `04-separability-experiment.md` | 环境实测、静态闭包、缩减链接实验、可行性判定与工作量估计 | 只读侦察 + 真实编译/链接（scout） |
| `closure.py` | 静态 `use` 传递闭包分析脚本（236 行），支持 `--only-main` | 实验产物 |
| `closure-output.txt` | `closure.py` 的两份真实运行输出（455 行） | `python3 closure.py` |
| `reduced-link-output.txt` | 缩减链接实验真实的 undefined reference 原始输出（71 行） | 手工重新链接 |
| `environment.txt` | 工具链与第三方库实测输出 | `which` / `pkg-config` / `ldconfig` |

## 复现

```bash
# 静态闭包分析
python3 docs/_recon/closure.py             > docs/_recon/closure-output.txt
python3 docs/_recon/closure.py --only-main >> docs/_recon/closure-output.txt

# 真实构建（仅需 mctc-lib，联网自动 FetchContent 拉取）
cmake -S . -B /tmp/xtb-red2/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=OFF
cmake --build /tmp/xtb-red2/build -j

# GFN2 单点验证
printf '3\nwater\nO 0.0 0.0 0.0\nH 0.0 0.0 0.96\nH 0.93 0.0 -0.24\n' > /tmp/w.xyz
XTBPATH=$PWD /tmp/xtb-red2/build/xtb /tmp/w.xyz --gfn2 --sp
```

## 已知偏差（引用时请留意）

`closure.py` 的词法闭包有两个方向的偏差：

- **高估**：`#if WITH_TBLITE` 保护的 `use tblite_*` 会被计入，预处理后其实不存在。以 `-DWITH_TBLITE=OFF` 的实测结果为准。
- **低估**：`integer, external :: lin` / `ncore` / `valijkl` 这类隐式外部过程不会出现在模块闭包里，但链接时必需。

主文档 §4.3 / §4.4 已分别说明并给出实测证据。
