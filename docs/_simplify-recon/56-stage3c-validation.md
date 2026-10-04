# 56 — 阶段 3c 独立验证报告（R5 档位四轴 + §3.10 再基线）

> **验证者独立复跑，未采信实施者报告（`55-stage3c-impl.md`）的任何数字。**
> 源码树 = 工作树（相对 `8b85c6d` 有 12 个文件的未提交改动；`src/`/`test/` 一字未动）。
> 独立构建 `/tmp/xtb-3c-val/build`（`-O2 -DNDEBUG`），所有 `OMP_NUM_THREADS=1`。
> 对照二进制 `/tmp/xtb-3bf/build/xtb`（基线 145 测试）。注入用 `cp -al` 硬链接副本
> `/tmp/xtb-3c-inj`（**不触碰仓库 src**）+ 独立构建 `/tmp/xtb-3c-inj-build`。

---

## 0. 结论

**通过。可以提交。**

- `ctest -R landscape` = **146 / 146**，回归子集 = **12 / 12**，无 `add_test` 重名，集合 S 差集 = 0。
- 四轴（`e_tol`/`acc`/`max_steps`/倍数）**逐档实测**与设计 §3.5、上游 `get_optthr` 表**逐值一致**。
- 三个轴**各自可证伪**（三次真注入，全部复现实施者报告里的失败消息，还原后绿）。
- §3.10 再基线：**唯一移动的已验收数字 = 默认步预算 256 → 200（有意）**，其余全部逐位/逐位精度不变。
- 两处非阻塞发现（§6）：模块级可变 `acc_was_set`；`--ohess <LEVEL>` 两半 SCF 精度不一致。

---

## 1. 构建与测试（T1）

```
$ cmake -S ... -B /tmp/xtb-3c-val/build -DWITH_TBLITE=OFF -DWITH_CPCMX=OFF -DWITH_TESTS=ON \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS_RELEASE="-O2 -DNDEBUG"
$ cmake --build /tmp/xtb-3c-val/build -j        # exit 0
```

| 检查 | 结果 |
|---|---|
| `ctest -R landscape -j4` | **146/146 passed**（`Total Test time 15.43 s`） |
| `ctest -R 'Singlepoint\|GFN\|model-hessian\|optimizer\|Argparser\|CAPI'` | **12/12 passed** |
| `grep -oE 'add_test("[^"]+"' test/unit/CMakeLists.txt \| sort \| uniq -d` | 空（无重名） |
| `ctest -N -R landscape` | `Total Tests: 146`（新测试 `xtb/landscape-level-axes` 出现一次） |
| 集合 S（`landscape_help_check.py main.F90 xhelp.f90`） | S(main)=S(help)=**135**，两种口径差集 **0** → `PASS: set S is documented` |

---

## 2. T2 — 四轴逐档实测（`--lopt --lopt-level <档>`，H2O n=3）

命令：`xtb landscape_h2o.xyz --gfn2 --lopt --lopt-level <档> --norestart`，`grep` 三行回显。

| 档位 | `maximum number of steps` | `energy tolerance` | `landscape engine: SCC accuracy` | 期望 | 判定 |
|---|---|---|---|---|---|
| superloose | 200 | **5.000000E-04** | **3.000000** | 5e-4 / 3.0 / 200 | ✅ |
| loose | 200 | **5.000000E-05** | **2.000000** | 5e-5 / 2.0 / 200 | ✅ |
| normal | 200 | **5.000000E-06** | **1.000000** | 5e-6 / 1.0 / 200 | ✅ |
| tight | 200 | **1.000000E-06** | **0.200000** | 1e-6 / 0.2 / 200 | ✅ |
| vtight | 200 | **1.000000E-07** | **0.050000** | 1e-7 / 0.05 / 200 | ✅ |
| **默认**（无 level） | **200** | 5.000000E-06 | 1.000000 | normal 派生 | ✅ |

`max_steps` 手算核对：n=3，倍数 1/2/3/5/20 → 3/6/9/15/60，全部 < 200 ⇒ `clamp` 下界 200 绑定，
5 档皆 200，与实测一致。（倍数的原子数缩放由单测 `level-step-budget` 覆盖，见 §5。）

T3 回显（其余任务，实测）：
- `--lscan --lscan-mode relaxed` → `energy tolerance: 5.000000E-06 Eh`，无 rigid 提示；
- `--lscan --lscan-mode rigid` → `energy tolerance: 5.000000E-06 Eh` + `(not used: a rigid scan runs no inner relaxation)`；
- `--lvib` → `energy tolerance: 5.000000E-06 Eh` + `(not used: the frequency task has no convergence loop)`；
- `--lts` / `--lirc` 的同构回显由对应单测/CLI 测试覆盖（`ctest` 146 绿）。

`--opt`/`--ohess` 桥（ranked keyword，实测）：

| 运行 | minimisation 半 | vib 半 |
|---|---|---|
| `--opt`（default） | level=normal，acc 1.000000，e_tol 5e-6，steps 200 | — |
| `--opt loose` | level=loose，acc **2.000000**，e_tol **5e-5** | — |
| `--opt tight` | level=tight，acc **0.200000**，e_tol **1e-6** | — |
| `--ohess tight` | level=tight，acc **0.200000**，e_tol **1e-6** | acc **1.000000**，e_tol 5e-6（未派生） |

---

## 3. T3 — 优先级（实测）

| 用例 | 实测 |
|---|---|
| `--lopt --lopt-level loose --acc 1.0` | acc **1.000000**（显式 `--acc` 胜），e_tol 仍 5e-5 ⇒ ✅ |
| `--lopt --lopt-level tight --lopt-max-steps 8` | steps **8** ⇒ ✅ |
| 反序 `--lopt-max-steps 8 --lopt-level tight` | steps **8** ⇒ **顺序无关** ✅ |
| `--lopt --lopt-level tight --cycles 4` | steps **4**（exit 1：预算不足未收敛，既有语义）⇒ ✅ |
| `--cycles 4 --lopt-max-steps 8`（异值） | **报错** `--cycles 4 conflicts with --lopt-max-steps 8: give only one step budget`，exit 1 ⇒ ✅ |
| `--cycles 8 --lopt-max-steps 8`（同值） | steps **8**，exit 0 ⇒ 幂等 ✅ |

R27（已知名集合不变）：`--lopt --lopt-level lax` → `Unknown landscape convergence level 'lax'`，exit 1 ⇒ ✅。

---

## 4. 证伪 — 三次真注入（独立构建，复现实施者消息）

副本 `/tmp/xtb-3c-inj`（`cp -al` + 解开被改文件硬链接），只改副本，`cmake --build --target xtb-exe`。

| # | 注入 | 原始 CLI 回显 | 独立跑 `landscape_cli_check.py levelaxes` |
|---|---|---|---|
| 1 | `main.F90` lopt 写入点 `if (acc_was_set) lset%engine%acc = set%acc` → 无条件 | `--lopt-level loose` 的 acc 回到 **1.000000**（死旋钮重现），e_tol 仍 5e-5 | exit 1：`FAIL: --lopt-level loose does not report acc 2.0 (dead knob, T2)` ✅ |
| 2 | `settings.f90` loose 档 `self%e_tol = 5.0e-5` → `5.0e-6` | loose 档 e_tol 回显 **5.000000E-06** | exit 1：`FAIL: --lopt-level loose does not report e_tol 5e-5 (T3)` ✅ |
| 3 | 删掉分派点 `call lset%level_step_budget(mol%n)` | 默认 `--lopt` 步预算回到 **256** | exit 1：`FAIL: the default level does not report clamp(3n, 200, 10000) = 200` ✅ |

三个轴各自可证伪，三条消息与 `55-stage3c-impl.md` §1 一字不差。

---

## 5. T4 — §3.10 再基线（与 HEAD 二进制对比）

### 5.1 M3/M7 链（`landscape_e2e_check.py chain`，`--lopt --lopt-level tight`）

| 值 | 3c 新二进制 | HEAD `3bf` | 判定 |
|---|---|---|---|
| `max dfreq` | **0.0100 cm^-1** | **0.0100 cm^-1** | 未动 ✅ |
| 频率 | 1539.58 / 3643.01 / 3651.17 | 同 | 未动 ✅ |
| dZPE | 1.429e-08 | 1.429e-08 | 未动 ✅ |
| dH | 1.427e-08 | **1.426e-08** | 末位差（~1e-10，舍入噪声） |
| dG | 1.430e-08 | **1.429e-08** | 末位差（~1e-10，舍入噪声） |

⇒ **M3/M7 已验收的 dfreq 0.0100 未动**；dH/dG 末位 1e-10 是独立进程浮点噪声，不构成移动。

### 5.2 模型势单测打印值（`ctest -R ... -V`）

| 值 | 报告 49 表 | 本轮实测 | 判定 |
|---|---|---|---|
| M4 prfo-vs-bprfo RMSD | 6.3022e-06 | **6.3022E-06** | 未动 ✅ |
| M4 dimer-vs-prfo RMSD | 7.7397e-05 | **7.7397E-05** | 未动 ✅（**实施者列为"未重测"，本轮实测闭合**） |
| M5 LEPS 解析势垒 | 8.9985 | **8.9985** | 未动 ✅ |
| M5 NEB 势垒 | 8.9985 | **8.9985 +0.0000** | 未动 ✅ |
| M5 CI-NEB | 8.9985 | **8.9985 +0.0000** | 未动 ✅ |
| M5 MB band | 105.7730 | **105.7730** | 未动 ✅ |
| M5 AutoNEB | 105.7230 | **105.7230** | 未动 ✅ |
| M6 MEP dev fwd | 0.03995/0.00657/0.00215/0.02574 | **同** | 未动 ✅ |
| M6 MEP dev bwd | 0.04132/0.01913/0.01395/0.02806 | **同** | 未动 ✅ |
| M6 LEPS crosscheck rmsd | 0.04440420 / 0.04136695 | **同** | 未动 ✅ |

⇒ 全部模型势数字（不驱动 SCF）**逐位不变**，符合静态预期，且已实测。

### 5.3 移动的数字

| 数字 | 旧 | 新 | 有意？ | 依据 |
|---|---|---|---|---|
| 默认 `--lopt` 步预算（H2O） | 256 | **200** | ✅ 有意 | `clamp(3·3,200,10000)` = 上游 `get_optthr` 规则；golden 已按新语义改写（`xtb/landscape-opt-knobs` 断言 200，**唯一被更新的 golden**，`git diff` 确认） |
| 其余全部 | — | — | ❌ 未动 | §5.1/§5.2 |

**未做项（本验证也未做，与实施者一致）**：M2 滞回 77 文件未重跑；M3 CH3OH dfreq 0.0600 未重跑
（人工实验、不在 ctest；默认档 `acc`/`e_tol` 逐字不变、仅预算 256→200，判定不受实质影响）。

---

## 6. T5 — 默认档影响（实测）

`--lopt`（无 level）：`maximum number of steps` **256 → 200**；`energy tolerance` 5.000000E-06（不变）；
`SCC accuracy` 1.000000（不变）。与 §2 默认行一致 ⇒ **E1 语义变化只落在步预算**。

---

## 7. 发现（findings）

1. **[LOW / 设计债] 模块级可变变量**：`src/prog/main.F90:138 logical :: acc_was_set = .false.`
   是 `xtb_prog_main` 模块里**唯一**的模块级变量，违反 AGENTS §5「No module-level mutable variables」。
   *事实*：`parseArguments` 开场复位（`:1823`，位于 flag 循环之前，所有返回路径都经过），
   `xtbMain:275` 每次运行都调 `parseArguments` ⇒ 单进程/C-API 重入安全（已读代码确认，非仅静态推断）。
   *建议*：后续可改为 `parseArguments` 的 `intent(out)` 出参或放进设置对象，消除模块级状态；
   当前实现功能正确，不阻塞提交。任务书原话「声明在 `program xtb` 局部」在模块结构下不可行，
   实施者的模块级选择是合理近似。
2. **[LOW / 待决策] `--ohess <LEVEL>` 两半 SCF 精度不一致**：minimisation 半 acc=0.2、vib 半 acc=1.0
   （实测 §2）。设计 §3.5 只写「档位驱动该运行的 SCF 精度」，未明确两半是否同精度；
   实施者在 §7.1 主动留作复核项。建议由设计定夺是否把档位 acc 同步给 `lvset%engine%acc`。
   不阻塞提交。

> 非 3c 问题（记录以免误判）：`--opt-level tight` 被参数解析器**静默接受**且不设档位
> （正确语法是 `--opt tight` ranked keyword）。这是既有 argparser 行为，与 3c 无关。

---

## 8. 被证伪的前提（独立复核）

- 实施者 §5.1「22 处 `set_conv_level` 调用点全部仍绿、只更新 1 处 golden」——**成立**：
  `ctest -R landscape` 146/146，`git diff --stat` 显示测试侧仅 `landscape_cli_check.py` 的
  256→200 与新增用例，无其他 golden 改动。
- 实施者 §4 未做项 #2（dimer-vs-prfo 7.7397e-05 未测）——**本轮实测通过（值不变）**，该项可销。
- 实施者 §5.4「加 `(not used: ...)` 提示会误红 `landscape-hess-step-used`」——测试全绿，
  `findall` + 只拒含 `Hessian`/`finite` 的 notice 的修正在 `xtb/landscape-hess-step-used` 上成立。

---

## 9. 复现命令

```bash
XTB=/tmp/xtb-3c-val/build/xtb; W=/tmp/xtb-3c-val/build/test/unit/landscape_h2o.xyz
for l in superloose loose normal tight vtight; do
  OMP_NUM_THREADS=1 $XTB $W --gfn2 --lopt --lopt-level $l | \
    grep -E "maximum number of steps|SCC accuracy|energy tolerance"; done
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-3c-val/build -R landscape
python3 test/unit/landscape_e2e_check.py chain $XTB $W /tmp/chain     # 对比 /tmp/xtb-3bf/build/xtb
OMP_NUM_THREADS=1 ctest --test-dir /tmp/xtb-3c-val/build -R '^xtb/landscape-(saddle|path|irc)$' -V
```
