# 02 — CLI 现状审计（调查员 B）

> **性质**：只调查，不改代码。本文件是本次唯一的产出。
> **基线**：`HEAD = 24c069f`（M0..M7 已提交）。所有行号以该提交为准。
> **证据纪律**：每条结论给出 `file:line`；凡未实测的一律标「未验证」。
> 实测二进制：`/tmp/xtb-land/build/xtb`（本次构建，`unknown-commit`）与参照
> `/home/owenchan/programs/xtb/bin/xtb`（6.7.1 edcfbbe，静态链接）。
> 所有 xtb 运行均 `OMP_NUM_THREADS=1`，工作目录在 `/tmp/cliaudit/` 下，**未触碰
> `/tmp/xtb-land/build`**（只读调用二进制）。

---

## 0. 结论摘要（先看这段）

| 问题 | 答案 |
|---|---|
| 参数总量 | **230 个拼写**（213 个 case 标签）：原生 **108**，套件新增 **122** |
| 是否「扩展」 | **解析层面是纯增量**（`xhelp.f90` 0 行删除；既有 case 体逐字未变）。**但行为上不是超集**：`--lvib` 覆盖 `$thermo`、`--lscan` 默认双向、`--lscan-fc` 默认差 10×、输出文件名与上游同名 |
| 已实现未文档化 | **30** 个（全部原生，套件 **0**） |
| 已文档化未实现 | `xhelp.f90` **4 个拼写 / 3 个选项**（全部原生：`--ithr`、`--xparam`、`-s|--silent`）；另 `AGENTS.md:130` 虚构 1 个套件选项（`--lts-printlevel`） |
| 文档/代码语义不一致 | 5 条（见 §2.3），其中 2 条与套件直接相关 |
| 套件子选项是否都在 `--help` | **是，122/122，0 缺失**（推翻任务书的「25 个」前提，见 §6.1） |
| 危险默认 | 10 条（见 §3.3） |
| 直觉性问题 | 命名不一致 4 组、`-step` 三种含义两种单位、必填项报错不点 flag 名、冲突组合静默首选项获胜（见 §4） |
| CLI 测试 | 75 个套件 CLI 测试；**58 个套件参数无任何 CLI 测试引用**，其中 **4 个在整个仓库里除 main.F90/xhelp.f90 外零引用** |

---

## 1. 参数全集（机器可核）

### 1.1 解析入口

- `src/prog/main.F90:1537` `do while (allocated(flag))` → `:1546` `select case (flag)` → `:3832` `end select` → `:3833` `end do`。
- 顶层 case 标签（9 空格缩进）共 **215** 个，其中 2 个（`:592`、`:610`）属于
  `select case (set%runtyp)`，**真正的 CLI case 标签 = 213 个**。
- 嵌套 case（`--color` 的 `auto|always|never`、`--lscan/lts/lirc-restart` 的 `off|pin|warm`、
  `--wrtopo` 的列表键、`selectList` 的 12 个键）不计入 CLI 参数。

统计命令（可复现）：

```bash
grep -cE '^ {9}case \(' src/prog/main.F90          # 215
grep -cE '^ {9}case \(' src/prog/main.F90          # 减去 :592 :610 → 213
```

### 1.2 数量

| 分类 | case 标签 | flag 拼写 |
|---|---|---|
| 原生（上游 6.7.1 已有） | 92 | **108** |
| 套件新增（`--ljson` + `--lopt*` + `--lscan*` + `--lts*` + `--lirc*` + `--lvib*`） | 121 | **122** |
| 合计 | 213 | **230** |

套件内部分布：`--ljson` 1、`--lopt*` 5、`--lscan*` 21、`--lts*` **56**、`--lirc*` 28、`--lvib*` 11。

> 任务书说「`--lts-*` 子选项此前实测约 30 个」→ 实测 **56**（`--lts` 本身含在内）。
> 统计命令：`grep -oE "'--lts[^']*'" src/prog/main.F90 | sort -u | wc -l`

### 1.3 套件新增参数全表（解析行 / 目标字段 / 是否有参数 / 有无 CLI 测试）

「target field」由 case 体内 `lXset%字段=` 的赋值自动抽取；`(runtyp only)` 表示该 flag 只调用
`set_runtyp`（如 `--lopt` 本身）。「CLI test」= `test/` 下的 cmake/py 测试里是否出现过该 flag 字面量。

| main.F90:line | flag(s) | arg | target field | CLI test |
|---|---|---|---|---|
| 2194 | `--ljson` | - | ljson | yes |
| 2207 | `--lopt` | - | (runtyp only) | yes |
| 2214 | `--lopt-engine` | Y | algorithm | yes |
| 2229 | `--lopt-level` | Y | conv thresholds (5 fields) | yes |
| 2243 | `--lopt-hessian` | Y | hessian_source | yes |
| 2259 | `--lscan` | - | (runtyp only) | yes |
| 2265 | `--lscan-mode` | Y | mode | yes |
| 2279 | `--lscan-method` | Y | method | yes |
| 2293 | `--lscan-level` | Y | conv thresholds (5 fields) | yes |
| 2307 | `--lscan-restart` | Y | engine%restart_mode, engine.restart_mode | **NO** |
| 2326 | `--lscan-ndim` | Y | ndim | yes |
| 2341 | `--lscan-oneway` | - | bidirectional | **NO** |
| 2346 | `--lscan-cold-start` | - | warm_start | **NO** |
| 2351 | `--lscan-fc` | Y | constraint_fc | **NO** |
| 2366 | `--lscan-expo` | Y | spring_expo | **NO** |
| 2381 | `--lscan-coord` | Y | coord(1)%ctype, coord(1).ctype | yes |
| 2396 | `--lscan-atoms` | Y | (runtyp only) | yes |
| 2406 | `--lscan-step` | Y | coord(1|2).step | yes |
| 2422 | `--lscan-nstep` | Y | coord(1)%nstep, coord(1).nstep | yes |
| 2437 | `--lscan-coord2` | Y | coord(2)%ctype, coord(2).ctype, ndim | yes |
| 2453 | `--lscan-atoms2` | Y | ndim | yes |
| 2464 | `--lscan-step2` | Y | coord(1|2).step, ndim | yes |
| 2481 | `--lscan-nstep2` | Y | coord(2)%nstep, coord(2).nstep, ndim | yes |
| 2497 | `--lscan-max-steps` | Y | max_steps | yes |
| 2512 | `--lscan-hessian` | Y | hessian_source | yes |
| 2528 | `--lscan-hessian-file` | Y | hessian_file | **NO** |
| 2538 | `--lts` | - | (runtyp only) | yes |
| 2544 | `--lts-method` | Y | method, path%climb, path.climb | yes |
| 2567 | `--lts-trust` | Y | trust | **NO** |
| 2582 | `--lts-trust-max` | Y | trust_max | **NO** |
| 2597 | `--lts-hlow` | Y | hlow | **NO** |
| 2612 | `--lts-max-steps` | Y | max_steps | yes |
| 2627 | `--lts-level` | Y | conv thresholds (5 fields) | yes |
| 2641 | `--lts-mode-overlap-min` | Y | mode_overlap_min | **NO** |
| 2656 | `--lts-alpha` | Y | alpha | **NO** |
| 2671 | `--lts-micro-cycles` | Y | max_micro_cycles | **NO** |
| 2686 | `--lts-target-mode` | Y | target_mode | **NO** |
| 2701 | `--lts-init-mode` | Y | init_mode | **NO** |
| 2715 | `--lts-delta` | Y | delta | yes |
| 2731 | `--lts-dr` | Y | dR | **NO** |
| 2746 | `--lts-rot-max-iter` | Y | rot_max_iter | **NO** |
| 2761 | `--lts-rot-alpha` | Y | rot_alpha | **NO** |
| 2776 | `--lts-rot-frms` | Y | rot_f_rms_th | **NO** |
| 2792 | `--lts-ninit` | Y | n_init | yes |
| 2806 | `--lts-seed` | Y | seed | yes |
| 2821 | `--lts-step-max` | Y | step_max | **NO** |
| 2836 | `--lts-translate-max-iter` | Y | translate_max_iter | **NO** |
| 2852 | `--lts-recalc` | Y | recalc | **NO** |
| 2867 | `--lts-no-verify` | - | verify_ts | yes |
| 2871 | `--lts-no-rigid` | - | remove_rigid | **NO** |
| 2876 | `--lts-restart` | Y | engine%restart_mode, engine.restart_mode | **NO** |
| 2895 | `--lts-hessian` | Y | hessian_source | **NO** |
| 2909 | `--lts-hessian-file` | Y | hessian_file | **NO** |
| 2919 | `--lts-step` | Y | engine%hess_step, engine.hess_step | yes |
| 2935 | `--lts-sccacc` | Y | engine%hess_acc, engine.hess_acc | yes |
| 2951 | `--lts-step0` | Y | step0 | yes |
| 2966 | `--lts-escape-step` | Y | escape_step | yes |
| 2983 | `--lts-product` | Y | path%product_file, path.product_file | yes |
| 2994 | `--lts-images` | Y | path%n_images, path.n_images | yes |
| 3009 | `--lts-kmin` | Y | path%k_min, path.k_min | **NO** |
| 3024 | `--lts-kmax` | Y | path%k_max, path.k_max | **NO** |
| 3039 | `--lts-kdecay` | Y | path%k_decay, path.k_decay | **NO** |
| 3054 | `--lts-no-dynamic-k` | - | path%use_dynamic_k, path.use_dynamic_k | **NO** |
| 3059 | `--lts-climb` | - | path%climb, path.climb | **NO** |
| 3064 | `--lts-climb-switch` | Y | path%climb_switch_rms, path.climb_switch_rms | **NO** |
| 3080 | `--lts-no-idpp` | - | path%ifidpp, path.ifidpp | **NO** |
| 3085 | `--lts-no-align` | - | path%align, path.align | **NO** |
| 3090 | `--lts-relax-ends` | - | path%relax_ends, path.relax_ends | yes |
| 3095 | `--lts-max-displ` | Y | path%max_displ, path.max_displ | **NO** |
| 3110 | `--lts-frms-avg` | Y | path%f_rms_avg_tol, path.f_rms_avg_tol | yes |
| 3125 | `--lts-frms-max` | Y | path%f_rms_max_tol, path.f_rms_max_tol | yes |
| 3140 | `--lts-autoneb-nstart` | Y | path%autoneb_nstart, path.autoneb_nstart | yes |
| 3155 | `--lts-autoneb-max-paths` | Y | path%max_paths, path.max_paths | yes |
| 3170 | `--lts-autoneb-max-depth` | Y | path%max_depth, path.max_depth | yes |
| 3185 | `--lts-autoneb-restart` | Y | path%autoneb_restart_file, path.autoneb_restart_file | yes |
| 3196 | `--lts-string-nnodes` | Y | path%string_nnodes, path.string_nnodes | yes |
| 3211 | `--lts-string-grow-tol` | Y | path%string_grow_tol, path.string_grow_tol | **NO** |
| 3226 | `--lts-string-ds` | Y | path%string_ds, path.string_ds | yes |
| 3241 | `--lts-string-nu2` | Y | path%string_nu2, path.string_nu2 | **NO** |
| 3256 | `--lts-string-grow-steps` | Y | path%string_grow_steps, path.string_grow_steps | **NO** |
| 3271 | `--lts-no-string-spline` | - | path%string_spline, path.string_spline | yes |
| 3276 | `--lts-string-history` | - | path%string_history, path.string_history | **NO** |
| 3281 | `--lirc` | - | (runtyp only) | yes |
| 3288 | `--lirc-method` | Y | method | yes |
| 3304 | `--lirc-step` | Y | step_length | yes |
| 3320 | `--lirc-max-steps` | Y | max_steps | yes |
| 3335 | `--lirc-level` | Y | conv thresholds (5 fields) | yes |
| 3351 | `--lirc-swap` | - | swap | yes |
| 3356 | `--lirc-oneway` | - | both_directions | yes |
| 3361 | `--lirc-target-mode` | Y | target_mode | yes |
| 3376 | `--lirc-micro-cycles` | Y | max_micro_cycles | **NO** |
| 3391 | `--lirc-micro-thresh` | Y | micro_step_thresh | yes |
| 3406 | `--lirc-euler-n` | Y | euler_n | **NO** |
| 3421 | `--lirc-loose-cycles` | Y | loose_cycles | yes |
| 3437 | `--lirc-mbs-tol` | Y | mbs_tol | yes |
| 3453 | `--lirc-mbs-max-k` | Y | mbs_max_k | yes |
| 3468 | `--lirc-mbs-points` | Y | mbs_points | **NO** |
| 3483 | `--lirc-dwi-n` | Y | dwi_n | yes |
| 3500 | `--lirc-e-rise`, `--lirc-erise-steps` | Y | e_rise_steps | yes |
| 3515 | `--lirc-grad-tol` | Y | grad_tol | yes |
| 3530 | `--lirc-recalc` | Y | hessian_recalc | **NO** |
| 3545 | `--lirc-no-endpoint-relax` | - | endpoint_relax | yes |
| 3550 | `--lirc-endpoint-relax` | - | endpoint_relax | yes |
| 3556 | `--lirc-rmsd-end` | Y | rmsd_end | yes |
| 3573 | `--lirc-hessian` | Y | hessian_source | **NO** |
| 3587 | `--lirc-hessian-file` | Y | hessian_file | **NO** |
| 3597 | `--lirc-step-hess` | Y | engine%hess_step, engine.hess_step | **NO** |
| 3612 | `--lirc-sccacc` | Y | engine%hess_acc, engine.hess_acc | **NO** |
| 3627 | `--lirc-restart` | Y | engine%restart_mode, engine.restart_mode | **NO** |
| 3646 | `--lvib` | - | (runtyp only) | yes |
| 3652 | `--lvib-hessian` | Y | hessian_source | yes |
| 3666 | `--lvib-hessian-file` | Y | hessian_file | yes |
| 3677 | `--lvib-step` | Y | engine%hess_step, engine.hess_step | **NO** |
| 3692 | `--lvib-sccacc` | Y | engine%hess_acc, engine.hess_acc | **NO** |
| 3707 | `--lvib-odlr` | - | engine%odlr, engine.odlr | yes |
| 3714 | `--lvib-no-project` | - | project_tr | **NO** |
| 3719 | `--lvib-temp` | Y | n_temperature, temperature, temperature(1) | yes |
| 3736 | `--lvib-rotor-cutoff` | Y | rotor_cutoff | **NO** |
| 3751 | `--lvib-imag-cutoff` | Y | imag_cutoff | yes |
| 3767 | `--lvib-freq-scal` | Y | freq_scal | **NO** |
| 3782 | `--lopt-hessian-file` | Y | hessian_file | **NO** |

### 1.4 原生参数全表（解析行 / 拼写 / 是否有参数）

| main.F90:line | flag(s) | arg |
|---|---|---|
| 1548 | `-h`, `--help` | - |
| 1552 | `--citation` | - |
| 1556 | `--license` | - |
| 1560 | `--version` | - |
| 1564 | `-v`, `--verbose` | - |
| 1567 | `-V`, `--very-verbose` | - |
| 1571 | `--define` | - |
| 1574 | `-P`, `--parallel` | Y |
| 1590 | `--restart` | - |
| 1593 | `--norestart` | - |
| 1596 | `--copy` | - |
| 1599 | `--nocopy` | - |
| 1602 | `--strict` | - |
| 1605 | `-I`, `--input` | Y |
| 1611 | `--namespace` | Y |
| 1617 | `--vparam` | Y |
| 1625 | `--coffee` | - |
| 1628 | `-a`, `--acc` | Y |
| 1649 | `-c`, `--chrg`, `--charge` | Y |
| 1684 | `-u`, `--uhf` | Y |
| 1692 | `--efield` | Y |
| 1705 | `--gfn` | Y |
| 1716 | `--gfn1` | - |
| 1722 | `--gfn2` | - |
| 1727 | `--gfn0` | - |
| 1733 | `--gfnff` | - |
| 1736 | `--gff` | - |
| 1739 | `--mcgfnff` | - |
| 1742 | `--iff` | - |
| 1745 | `--ptb` | - |
| 1752 | `--tblite` | - |
| 1760 | `--color` | - |
| 1776 | `--spinpol` | - |
| 1784 | `--dipro` | Y |
| 1799 | `--oniom` | Y |
| 1822 | `--cut` | - |
| 1825 | `--etemp` | Y |
| 1835 | `--esp` | - |
| 1839 | `--stm` | - |
| 1843 | `--cma` | - |
| 1846 | `--tm` | - |
| 1849 | `--enso` | - |
| 1852 | `--json` | - |
| 1856 | `--ceasefiles` | - |
| 1868 | `--orca` | - |
| 1871 | `--driver` | Y |
| 1878 | `--mopac` | - |
| 1881 | `--pop` | - |
| 1884 | `--molden` | - |
| 1887 | `--dipole` | - |
| 1890 | `--wbo` | - |
| 1893 | `--lmo` | - |
| 1897 | `--ewin` | Y |
| 1905 | `--fod` | - |
| 1909 | `--iterations`, `--maxiterations` | Y |
| 1918 | `--cycles` | Y |
| 1926 | `-g`, `--gbsa` | Y |
| 1962 | `--alpb` | Y |
| 1997 | `--gbe` | Y |
| 2012 | `--gb` | Y |
| 2027 | `--cosmo`, `--tmcosmo` | Y |
| 2061 | `--cpcmx` | Y |
| 2075 | `--scc`, `--sp` | - |
| 2078 | `--vip` | - |
| 2082 | `--vea` | - |
| 2086 | `--vipea` | - |
| 2090 | `--vomega` | - |
| 2094 | `--vfukui` | - |
| 2097 | `--alpha` | - |
| 2100 | `--raman` | Y |
| 2112 | `--grad` | - |
| 2116 | `-o`, `--opt` | Y |
| 2123 | `--hess` | - |
| 2126 | `--md` | - |
| 2129 | `--ohess` | Y |
| 2136 | `--bhess` | Y |
| 2143 | `--o1nh` | - |
| 2146 | `--imagmin` | Y |
| 2154 | `--imagmax` | Y |
| 2162 | `--omd` | - |
| 2166 | `--siman` | - |
| 2170 | `--path` | Y |
| 2177 | `--screen` | - |
| 2180 | `--gmd` | - |
| 2184 | `--modef` | Y |
| 2191 | `--mdopt` | - |
| 3792 | `--metadyn` | Y |
| 3800 | `--metaopt` | Y |
| 3807 | `--nat` | Y |
| 3813 | `--bias-input`, `--gesc` | Y |
| 3821 | `--wrtopo` | Y |
| 3830 | `--nocellopt` | - |

count: 92

---

## 2. 与 `src/xhelp.f90` 的双向对照

### 2.1 方法

从 `xhelp.f90` 提取「以 `-` 开头的行首选项串」（含 `"--a, --b"` 多别名与 `"--[no]copy"` 展开），
得 **204 个拼写**；与 main.F90 的 **230 个拼写** 做集合差。

| 集合 | 数量 |
|---|---|
| main.F90 拼写 | 230 |
| xhelp.f90 拼写 | 204 |
| 交集 | 200 |
| **只在 main.F90**（已实现未文档化） | **30** |
| **只在 xhelp.f90**（已文档化未实现） | **4** |

套件部分：main.F90 122 / xhelp.f90 122 / **差集双向均为 0**。

### 2.2 (a) 已实现但未文档化 —— 30 个（全部是原生参数）

```
--bias-input(main.F90:3813)  --charge(:1649)      --coffee(:1625)   --color(:1760)
--cut(:1822)                 --dipro(:1784)       --driver(:1871)   --enso(:1849)
--ewin(:1897)                --gesc(:3813)        --gfn0(:1727)     --gfn1(:1716)
--gfn2(:1722)                --gmd(:2180)         --iff(:1742)      --iterations(:1909)
--maxiterations(:1909)       --mcgfnff(:1739)     --mdopt(:2191)    --mopac(:1878)
--nat(:3807)                 --nocellopt(:3830)   --orca(:1868)     --screen(:2177)
--siman(:2166)               --tm(:1846)          --version(:1560)  --very-verbose(:1567)
-V(:1567)                    --wrtopo(:3821)
```

**套件新增参数 0 个未文档化** —— 这是本次审计对套件最正面的一条。

### 2.3 (b) 已文档化但未实现 —— 4 个拼写 / 3 个选项（全部是原生参数，套件 0）

| 选项 | xhelp 行 | 实测（本仓库二进制） |
|---|---|---|
| `--ithr REAL` | `src/xhelp.f90:717` | `-1- prog_main_parseArguments: Unknown option '--ithr' provided` |
| `--xparam FILE` | `src/xhelp.f90:170` | `Unknown option '--xparam' provided` |
| `-s`, `--silent` | `src/xhelp.f90:775` | `Unknown option '--silent' provided` / `Unknown option '-s' provided` |

实测命令：`/tmp/xtb-land/build/xtb --ithr` 等（每条都在 `-1-` 行给出 `Unknown option`）。
这是**上游既有**缺陷（未随套件变化），但它正是「本项目已抓到 3 次死旋钮」的同一类问题的现存实例，
只是发生在原生侧而不是套件侧。

**额外的文档虚假承诺（不在 xhelp 里，在 AGENTS.md 与 PLAN 里）：**

| 声明处 | 声明 | 实测 |
|---|---|---|
| `AGENTS.md:130` | `--lts-printlevel` 存在 | **不存在**：`grep -c printlevel src/prog/main.F90` = 0，`xhelp.f90` 亦 0 |
| `AGENTS.md:130` | `--lts-dimer-*` | **无此前缀**：`grep -c -- '--lts-dimer' src/prog/main.F90` = 0（dimer 参数是 `--lts-delta/--lts-dr/--lts-rot-*/--lts-ninit/--lts-seed/--lts-step0/--lts-step-max/--lts-translate-max-iter`） |
| `docs/xtb-landscape-PLAN.md:881` | 「提供 `--lts trust=0.1` 快捷档」 | 实现的是 `--lts-trust 0.1`（`main.F90:2567`）；`settings.f90:631` 的注释也仍写 `--lts trust=0.1` |
| `docs/xtb-landscape-PLAN.md:1207` | `--lts [method=prfo\|bprfo\|dimer]` | 实现的是 `--lts-method <name>`（`main.F90:2544`） |

统计命令：
```bash
grep -c printlevel src/prog/main.F90                       # 0
grep -c -- '--lts-dimer' src/prog/main.F90                 # 0
```

### 2.4 (c) 文档与代码的默认值 / 语义不一致 —— 5 条

| # | 位置 | 文档说 | 代码/实测 |
|---|---|---|---|
| c1 | `xhelp.f90:294-297` `--lopt-hessian SOURCE` | 「one of numerical (default) or model」 | `file` **也被接受并使用**：`landscape_hessian_source_known`（`src/landscape/types/hessian.f90:201-206`）含 `'file'`；实测 `--lopt --lopt-hessian file --lopt-hessian-file nope.dat` 打印 `Hessian source: file`。另外 4 个 `--lX-hessian` 的帮助都列了 `file`（`xhelp.f90:358,457,638,658`），只有 `--lopt-hessian` 漏了 |
| c2 | `xhelp.f90:388-389` `--lts-level LEVEL` | 只列等级名，**未写默认** | 默认 = `normal`（`settings.f90:357-365` 的初值恰等于 `set_conv_level('normal')`，`settings.f90:1040-1044`）。其余 3 个 level flag 里 `--lopt-level`（`xhelp.f90:290-291`）与 `--lscan-level`（`:332-333`）写了「normal (default)」，`--lirc-level`（`:568-570`）同样没写 |
| c3 | `xhelp.f90:653-657` `--lvib` | 「writes … thermochemistry … with the names and formats of `--hess`」 | **`--lvib` 会静默覆盖 xcontrol `$thermo` 的全部键**（见下 §2.5 实测）。`--lvib` 与 `--hess` 在这一点上**不等价** |
| c4 | `xhelp.f90:385-386` `--lts-max-steps N` | 「maximum number of macro iterations (default 256)」 | 它**同时**是 band 搜索的迭代预算（`main.F90:1006` `ltset%path%max_steps = ltset%max_steps`），而 `landscape_path_settings%max_steps` 自己的默认是 **512**（`settings.f90:208`）。⇒ 同一「band 迭代上限」在 CLI 入口是 256、在 API 入口是 512，文档只说了 256 |
| c5 | `AGENTS.md:130` | 见 §2.3 表 | 见 §2.3 表 |

（另：`xhelp.f90:690` 的原生 `--cycles [int]` 未深查，标「未验证」，不计入上表。）

### 2.5 c3 的实测证据（本次新发现，仓库既有文档里没有记录）

同一份 xcontrol、同一几何（`h2o.xyz`、GFN2），比较 `--hess` 与 `--lvib` 的热化学表：

```
$thermo
   temp=298.15,300.0,400.0
$end
```

```
### --hess -I thermo.inp
 298.15  VIB   1.00                    2.392      0.060      0.009
 300.00  VIB   1.00                    2.506      0.063      0.009
 400.00  VIB   1.00                   16.371      0.231      0.048
### --lvib -I thermo.inp
 298.15  VIB   1.00                    2.392      0.060      0.009      ← 只剩一个温度
```

```
$thermo
   scale=0.9000
   temp=298.15
$end
```
```
### --hess -I scale.inp      298.15  VIB   1.00     4.577      0.104      0.018
### --lvib -I scale.inp      298.15  VIB   1.00     2.392      0.060      0.009   ← 完全忽略 scale
```

机制（代码为准）：`src/landscape/vib/thermo.f90:167-180`

```fortran
ntemp = max(1, min(settings%n_temperature, size(set%thermotemp)))
set%nthermo = ntemp
set%thermotemp(1:ntemp) = settings%temperature(1:ntemp)
set%thermo_sthr = settings%rotor_cutoff
set%thermo_ithr = settings%imag_cutoff
set%thermo_fscal = settings%freq_scal
```

**无条件覆盖**，而 `lvset` 的默认是 `n_temperature = 1`、`temperature(1) = 298.15`
（`settings.f90:582-584`）。因此 `$thermo temp=…, …, …` 的列表、`sthr`、`imagthr`、`scale`
在 `--lvib` 下全部丢失；CLI 上也没有恢复手段（`--lvib-temp` 只读**一个数**：
`main.F90:3719-3733`，`read(sec,*,iostat=idum) ddum` 后 `n_temperature = 1`）。

补充观察（**未验证机制**）：`$thermo scale=0.9` 让 `--hess` 的 VIB 焓从 2.392 变成 4.577
cal/mol（约 1.9 倍，方向与直觉相反）。这条属于上游 `print_thermo` 路径，本次未追根因。

### 2.6 子选项是否都进了 `--help`（任务书点名要确切数字）

| 前缀 | main.F90 | xhelp.f90 | 缺失 |
|---|---|---|---|
| `--ljson` | 1 | 1 | 0 |
| `--lopt*` | 5 | 5 | 0 |
| `--lscan*` | 21 | 21 | 0 |
| `--lts*` | **56** | **56** | **0** |
| `--lirc*` | 28 | 28 | 0 |
| `--lvib*` | 11 | 11 | 0 |
| 合计 | **122** | **122** | **0** |

逐个列举「缺失者」：**没有缺失者**（集合差为空，双向）。

---

## 3. 默认值审计

### 3.1 套件新增参数默认值（`src/landscape/types/settings.f90` 为准）

| flag | 字段 | 默认值 | 依据（代码注释/文档） |
|---|---|---|---|
| `--lopt-engine` | `algorithm` | `lbfgs` | `settings.f90:427`；MAPLE `LBFGSParams.memory=5` 类比（`settings.f90:421`） |
| `--lopt-level` / `--lscan-level` / `--lts-level` / `--lirc-level` | 4 判据 + `e_tol` | `normal`（3.0e-4 / 1.0e-4 / 4.0e-3 / 2.0e-3，`e_tol=5e-6`） | ORCA 6.1 命名（`settings.f90:1023`），非 xtb 的 ANCopt 阈值 |
| `--lopt/lscan/lts/lirc/lvib-hessian` | `hessian_source` | `numerical` | `settings.f90:373`（中心差分） |
| `--lscan-mode` | `mode` | `relaxed` | `settings.f90:525` |
| `--lscan-method` | `method` | `lbfgs` | `settings.f90:528` |
| `--lscan-ndim` | `ndim` | `1` | `settings.f90:530` |
| `--lscan-oneway`（反向） | `bidirectional` | `.true.`（**默认双向**） | `settings.f90:534` |
| `--lscan-cold-start`（反向） | `warm_start` | `.true.` | `settings.f90:541` |
| `--lscan-fc` | `constraint_fc` | **0.5** hartree/bohr² | `settings.f90:545`；注释明说「**deliberately not** taken from `xtb_scanparam::fcconstr`」（`settings.f90:519-522`） |
| `--lscan-expo` | `spring_expo` | 2.0 | `settings.f90:543`（与 xtb `springexpo=2.0` 一致） |
| `--lscan-max-steps` | `max_steps` | 256 | `settings.f90:355` |
| `--lts-method` | `method` | `prfo` | `settings.f90:628` |
| `--lts-trust` | `trust` | 0.37795 bohr (0.2 Å) | `settings.f90:631` |
| `--lts-trust-max` | `trust_max` | 1.8897 bohr | `settings.f90:635` |
| `--lts-hlow` | `hlow` | 1.0e-2 | `settings.f90:643` |
| `--lts-mode-overlap-min` | `mode_overlap_min` | 0.3 | `settings.f90:656` |
| `--lts-alpha` | `alpha` | 0.5 | `settings.f90:659` |
| `--lts-micro-cycles` | `max_micro_cycles` | 50 | `settings.f90:661` |
| `--lts-target-mode` | `target_mode` | 1 | `settings.f90:653` |
| `--lts-init-mode` | `init_mode` | `h0` | `settings.f90:683` |
| `--lts-escape-step` | `escape_step` | 0.2 bohr | `settings.f90:699`（M4 MEDIUM-1 修复轮新增） |
| `--lts-delta` | `delta` | 1.8897e-2 bohr | `settings.f90:708`（pysisyphus 约定，**实测标定过**） |
| `--lts-dr` | `dR` | 1.8897e-3 | `settings.f90:711`（Henkelman-Jonsson） |
| `--lts-rot-max-iter` / `--lts-rot-alpha` / `--lts-rot-frms` | — | 5 / 0.5 / 2.65e-4 | `settings.f90:719 / :717 / :724` |
| `--lts-ninit` / `--lts-seed` | — | `random` / 42 | `settings.f90:741,746` |
| `--lts-step0` / `--lts-step-max` | — | 0.37795 / 0.28346 | `settings.f90:731,733`（实测首步 0.1032） |
| `--lts-translate-max-iter` | — | 1 | `settings.f90:737` |
| `--lts-recalc` | `recalc` | 1 | `settings.f90:663` |
| `--lts-step` / `--lvib-step` / `--lirc-step-hess` | `engine%hess_step` | 5.0e-3 bohr | `settings.f90:333` |
| `--lts-sccacc` / `--lirc-sccacc` / `--lvib-sccacc` | `engine%hess_acc` | 0.3 | `settings.f90:335` |
| `--lts-images` | `path%n_images` | 9 | `settings.f90:171` |
| `--lts-kmin` / `--lts-kmax` / `--lts-kdecay` | — | 1e-2 / 1e-1 / 0.5 | `settings.f90:173,175,180`（**LEPS 面标定**） |
| `--lts-climb-switch` | `climb_switch_rms` | 9.7234e-3 | `settings.f90:192`（0.5 eV/Å） |
| `--lts-max-displ` | `path%max_displ` | 0.37795 | `settings.f90:214` |
| `--lts-frms-avg` / `--lts-frms-max` | — | 3e-4 / 1e-3 | `settings.f90:203,206` |
| `--lts-autoneb-nstart/max-paths/max-depth` | — | 5 / 10 / 5 | `settings.f90:252,254,256` |
| `--lts-string-nnodes/grow-tol/ds/nu2/grow-steps` | — | 9 / 5e-3 / 0.5 / 5e-2 / 200 | `settings.f90:274-296` |
| `--lirc-method` | `method` | **`hpc`** | `settings.f90:814`（M6 修复轮**改过默认**，见 §3.3） |
| `--lirc-step` | `step_length` | 0.10 bohr·amu^½ | `settings.f90:822`（Gaussian `IRC=StepSize`） |
| `--lirc-max-steps` | `max_steps` | 256 | `settings.f90:355` |
| `--lirc-micro-cycles` / `--lirc-micro-thresh` | — | 20 / 1e-3 | `settings.f90:834,841` |
| `--lirc-euler-n` | `euler_n` | 5000 | `settings.f90:844`（Hratchian-Schlegel Eq.10） |
| `--lirc-loose-cycles` | — | 3 | `settings.f90:847`（MAPLE） |
| `--lirc-mbs-tol/max-k/points` | — | 1e-5 / 15 / 20 | `settings.f90:866,858,861` |
| `--lirc-dwi-n` | `dwi_n` | 4（仅分配容量，≥2 等价） | `settings.f90:855`（**实测** 4 vs 20 逐位相同） |
| `--lirc-e-rise` | `e_rise_steps` | 3 | `settings.f90:870`（**实测标定**，标 `[待校准]`） |
| `--lirc-grad-tol` | `grad_tol` | 1e-3 | `settings.f90:878`（MAPLE 端点判据上取整，标 `[待校准]`） |
| `--lirc-recalc` | `hessian_recalc` | -1（关闭） | `settings.f90:897`（**实测**：短路径够用、长路径需 5–10） |
| `--lirc-rmsd-end` | `rmsd_end` | 0.18897 bohr | `settings.f90:915`（MAPLE 0.1 Å） |
| `--lvib-temp` | `temperature(1)`, `n_temperature` | 298.15 K, 1 | `settings.f90:582-584` |
| `--lvib-rotor-cutoff` | `rotor_cutoff` | 50.0 cm⁻¹ | `settings.f90:589`（xtb `set%thermo_sthr`） |
| `--lvib-imag-cutoff` | `imag_cutoff` | -20.0 cm⁻¹ | `settings.f90:593` |
| `--lvib-freq-scal` | `freq_scal` | 1.0 | `settings.f90:596` |
| `--ljson` | `ljson` | `.false.` | `settings.f90:384` |
| `--lscan/lts/lirc-restart` | `engine%restart_mode` | `off` | `settings.f90:331` |

**依据分类统计**（粗略，以代码注释中的显式陈述为准）：

- **实测校准**（注释写「measured」并有报告编号）：`--lts-delta`、`--lts-step0`、
  `--lirc-e-rise`、`--lirc-grad-tol`、`--lirc-recalc`、`--lirc-dwi-n`、`--lts-kmin/kmax`（LEPS 面）。
- **文献/上游约定**：`--lirc-step`、`--lirc-euler-n`、`--lirc-mbs-*`、`--lirc-loose-cycles`、
  `--lts-dr`、`--lts-rot-*`、`--lirc-rmsd-end`、`--lts-climb-switch`。
- **xtb 惯例**：`--lvib-*` 的 5 个热化学参数、`--lX-hessian= numerical`、`--lX-hessian-file` 格式。
- **未标定（`[待校准]`）**：`--lirc-e-rise`、`--lirc-grad-tol`（`settings.f90:870,878` 仍保留标记）；
  `landscape_ts_settings` 的 4 个力判据「**not** re-calibrated for transition states」（`settings.f90:618`）。

### 3.2 没有 CLI 旋钮的字段（会导致「想调也调不了」）

用「字段名 → 是否有 flag 赋值」检查（`main.F90` 内 `lXset%字段=` 的精确匹配）：

| 类型 | 无 CLI 旋钮的字段 |
|---|---|
| `landscape_opt_settings` | `max_steps`、`printlevel`、`hessian_update`、`max_displ`、`trust_radius`、`lbfgs_memory`、`curvature`、`line_search`、`trust_min`、`evals_eps`、`mu_margin`、`max_bisect_it`、`eta_shrink`、`eta_expand`、`armijo_c1`、`max_backtrack`、`diis_*`(4)、`write_files`、`output_prefix` |
| `landscape_scan_settings` | `sequential`、`write_files`、`output_prefix` |
| `landscape_vib_settings` | `linear_tol`、`write_files` |
| `landscape_ts_settings` | `trust_min`、`eta_shrink`、`eta_expand`、`evals_eps`、`mu_margin`、`max_bisect_it`、`hessian_update`、`linear_tol`、`rot_dtheta`、`write_files`、`output_prefix` |
| `landscape_irc_settings` | `hessian_update`、`write_files`、`output_prefix` |
| `landscape_path_settings` | `printlevel`、`lbfgs_memory`、`curvature` |
| `landscape_engine_control` | `maxiter`、`printlevel`、`lgrad`、`hvp_step` |

验证命令（示例）：

```bash
grep -c 'lset%max_steps' src/prog/main.F90        # 0  → 没有 --lopt-max-steps
grep -c 'ltset%printlevel' src/prog/main.F90      # 0  → 没有 --lts-printlevel
grep -c 'lvset%linear_tol' src/prog/main.F90      # 0  → 没有 --lvib-linear-tol
```

**最值得注意的两条**：

1. **`--lopt-max-steps` 不存在**（而 `--lscan-max-steps`、`--lts-max-steps`、`--lirc-max-steps`
   都存在）。`--lopt` 迭代预算固定 256（`settings.f90:355`），用户无法提高。
2. **确认任务只能在 `--lvib` 下调**：`--lts` 也做频率确认，但 `--lts-project-tr`、
   `--lts-imag-cutoff`、`--lts-linear-tol` 都没有 flag，而 `--lvib` 有
   `--lvib-no-project`（`main.F90:3714`）与 `--lvib-imag-cutoff`（`:3751`）。

### 3.3 危险默认清单（逐条给出差异与理由）

| # | 默认 | 与什么不同 | 实测/证据 | 理由（代码注释） |
|---|---|---|---|---|
| D1 | `--lscan-fc` = **0.5** hartree/bohr² | xtb 自身 `fcconstr = 0.05`（`src/scanparam.f90:34`，用于 `src/scanparam.f90:77` 的约束势） | 同一 2 步 H2O 距离扫描：点 3 的 drift = **−0.02628 Å**（fc=0.5）vs **−0.08128 Å**（fc=0.05），能量 −5.0667602 vs −5.0702720 Eh | `settings.f90:519-522`「deliberately **not** taken from xtb globals」；M2 报告 13 §R2 记「与 `--scan` 默认不可比」 |
| D2 | `--lirc-method` = **`hpc`** | M6 之前默认 `gs` | `settings.f90:814`；M6 修复报告 46 记「行为变更（显式记录）：默认积分方法 gs → hpc」 | 实测 hpc 更准（MB 0.0022 vs 0.040 bohr）且便宜 8.5× |
| D3 | `--lopt-engine` = **`lbfgs`** | 上游 `--opt` 用 ANCopt（`src/optimizer.f90`） | `settings.f90:427` | 与 `--opt` 是完全不同的算法族（ANCopt 在 `src/optimizer.f90`），默认轨迹/步数必然不同（**未逐位对比，标「未验证」**） |
| D4 | `--lscan` 默认 **双向**（`bidirectional = .true.`） | 上游 relaxed scan 是**单向**（`src/scan_driver.f90:79-101` 只有 `do j = 1, nscan`，无反向循环） | 实测 `--lscan-nstep 2` 产生 **5** 帧（0.95888 / 1.00888 / 1.05888 / 1.00888 / 0.95888），即同 `nstep` 下约 **2×** 点数与成本 | `settings.f90:534`；M2 报告把双向当作 hysteresis 自检 |
| D5 | `--lvib` **覆盖** xcontrol `$thermo` 全部键 | `--hess` 尊重 `$thermo temp/sthr/imagthr/scale` | §2.5 实测：温度列表从 3 个变 1 个；`scale=0.9` 完全无效 | `vib/thermo.f90:167-180` 无条件覆盖 |
| D6 | 输出文件名与上游**同名** | `--lopt`→`xtbopt.xyz`+`xtb.trj`；`--lvib`→`hessian`/`vibspectrum`/`vib_normal_modes`/`g98.out`；`--lscan`→`xtbscan.log` | 实测 `--lopt` 目录内容：`xtbopt.xyz xtb.trj xtbtopo.mol charges wbo`；`--lvib`：`hessian vibspectrum vib_normal_modes g98.out xtbtopo.mol charges wbo` | 有意为之（工具链兼容）；缓解手段只有 `--namespace`（M7 才让 `--lopt` 也遵守，见 `types/log.f90`） |
| D7 | `--lts-escape-step` = 0.2 bohr **会先移动输入几何** | 一般 TS 搜索不会改起点 | 实测 `--lts --lts-level superloose` 从 H2O 极小点起步打印 `escape from a minimum: 0.200000 bohr along the lowest internal mode`，4692 次能量评估（对比：同一算例从 TS 猜测起步只需 95 次） | `settings.f90:699`；M4 MEDIUM-1 修复轮引入（否则「跟随最低模式上行」在极小点上无方向） |
| D8 | `--lvib` 默认 Eckart 投影（`project_tr = .true.`） | `--hess` 用 `trproj` | 频率差 ≤5.7 cm⁻¹（水，AGENTS §6）；非平稳几何可达 5.21 cm⁻¹ | `settings.f90:573`；两种投影在**不同度规**下定义同一刚体运动 |
| D9 | `--lts`/`--lirc` 的 `etemp` 全程**冻结** | 上游 `--opt` 无此语义 | `main.F90:996-997`、`:1025-1026` 把 `set%etemp` 拷进 `ltset/lircset` 并冻结；`xhelp.f90` 未提 | M4 硬约束 1（避免 P-RFO 模式跟随被温度抖动破坏） |
| D10 | `--ljson` 必须有套件 runtyp | 无 | 实测 `--ljson --opt`（原生）→ `[WARNING] --ljson writes nothing without a landscape run type: add --lopt, --lscan, --lvib, --lts or --lirc`（`main.F90:945-950`） | 文档已写明（`xhelp.f90:279`） |

---

## 4. 直觉性评估（全部有实测）

### 4.1 常见任务的参数条数

| 任务 | 上游 xtb | 套件 | 备注 |
|---|---|---|---|
| 单点 | `xtb m.xyz --gfn2` | **无 CLI**（`sp` 任务只有 API；`main.F90` 无 `--lsp`，`xhelp.f90:280` 亦声明「reachable through the API only」） | 必须用原生 |
| 极小化 | `xtb m.xyz --opt` | `xtb m.xyz --lopt` | 同长，但默认引擎不同（D3） |
| 频率 | `xtb m.xyz --hess` | `xtb m.xyz --lvib` | 同长；`--lvib` 覆盖 `$thermo`（D5） |
| 扫描 | `xtb m.xyz --opt` + xcontrol `$constrain`/`$scan` 块（≥8 行输入文件） | `--lscan --lscan-coord distance --lscan-atoms 1,2 --lscan-step 0.05 --lscan-nstep 10`（5 个 flag） | 套件更长但**自包含**；上游扫描没有 CLI |
| 过渡态 | **不存在** | `--lts`（默认 prfo），或 `--lts --lts-method neb --lts-product p.xyz` | |
| IRC | **不存在** | `--lirc`（默认 hpc） | |

实测（均可复现，全部 exit 0）：

```
--lopt  → landscape: lbfgs minimisation / converged            (6 次能量评估)
--lvib  → landscape: harmonic frequencies / 19 E / 1 Hessian
--lts   → landscape: transition state search (prfo) / 1 虚频 / converged (95 E)
--lirc  → landscape: intrinsic reaction coordinate (hpc) / 41+39 帧 / exit 0
--lts --lts-method dimer → 179 E，Hessians = 1（仅确认用）
```

### 4.2 必填 vs 可选（以及报错是否可读）

| 场景 | 实测报错 | 是否点出 flag 名 |
|---|---|---|
| `--lts --lts-method neb`（缺 `--lts-product`） | `landscape_ts_band: a band search needs a product geometry; pass it with --lts-product <file>` | ✅ **点名** |
| `--lvib --lvib-hessian file`（缺 file 名） | `the Hessian source 'file' needs --lvib-hessian-file`（`tasks/vib.f90:139`） | ✅ 点名 |
| `--lscan`（什么都没给） | `landscape_scan_check: atom index 0 of the distance coordinate is outside 1..3` | ❌ 不点 `--lscan-atoms` |
| `--lscan --lscan-coord … --lscan-atoms 1,2`（缺 step） | `landscape_scan_check: coordinate 1 has a zero step size` | ❌ 不点 `--lscan-step` |
| `--lscan … --lscan-atoms 1,2 --lscan-step 0.05`（缺 nstep） | `landscape_scan_check: coordinate 1 has nstep = 0, at least one step is required` | ❌ 不点 `--lscan-nstep` |

⇒ **M4 建立起来的「可操作诊断」约定没有推广到 M2 的 scan**。全部都是可读的（描述症状 + 退出码 1），
但只有 `--lts-product` / `--lvib-hessian-file` 两条给出了「加哪个 flag」。

（附带观察：失败路径一律 `ERROR STOP` + gfortran backtrace，输出噪声较大；
`--lts` 缺产物那条在 `-1-` 之前还有一行 `landscape task terminated: the product endpoint could not be read`。）

### 4.3 自动推导（可以省略什么）

- `--lts-method dimer` **不需要任何 Hessian 参数**：实测 `Hessians = 1`，仅用于最终虚频确认
  （搜索本身是纯一阶，`xhelp.f90:373` 已写明「first derivatives only, no Hessian」）。
- `--lts-method cineb|autoneb|string|gsm` **自动打开 climbing image**：`main.F90:2556-2559`，
  `xhelp.f90:488-490` 写明。
- `--lts-max-steps` 同时是 band 搜索的预算：`main.F90:1006` `ltset%path%max_steps = ltset%max_steps`
  （所以没有 `--lts-path-max-steps`）。这一点 xhelp 未说明。
- `--lscan-ndim` 可省略：给 `--lscan-coord2/-atoms2/-step2/-nstep2` 任一即自动 `ndim = 2`
  （`main.F90:2440,2456,2467,2484`），xhelp `:321-323` 已写明。

### 4.4 冲突组合是否被检测 —— **否，静默首选项获胜**

实测（同一几何、`--norestart`）：

```
--lopt --lscan --lscan-coord distance --lscan-atoms 1,2 --lscan-step 0.05 --lscan-nstep 1
   → landscape: lbfgs minimisation        （--lscan 及其 5 个子选项被完全忽略，exit 0，无任何提示）

--lscan ... --lopt
   → landscape: relaxed scan              （--lopt 被忽略，exit 0，无任何提示）

--opt --hess        → 跑 --opt，无提示
--hess --opt        → 跑 --hess，无提示
```

机制（**上游既有**）：`src/set_module.f90:1033-1038`

```fortran
subroutine set_runtyp(typ)
   logical,save :: set1 = .true.
   if (.not.set1) then
      call raise('S','Runtyp already set and locked, please use a composite runtyp instead.')
      return
   endif
```

- **首次调用获胜**；第二次调用进入 `raise('S', …)`。
- 套件 flag 用 `if (set%runtyp /= p_run_lxxx) call set_runtyp('lxxx')` 保护自己
  （如 `main.F90:2212, 2263, 2542, 3283, 3648`），所以同一个任务的多个 flag 不会互相触发锁；
  **但两个不同的任务 flag 仍然是「先到先得 + 静默丢弃后者」**。
- `raise('S', …)` 写进 `persistentEnv`（`src/mctc/error.f90:30`），而程序用的是
  `src/prog/primary.f90:38` 里 `call init(env)` 建出来的 `env`；`env%show` 在
  `src/prog/main.F90:1422` 打印的是**那个** env 的缓冲。实测：`--strict` 也不改变结果
  （`strict` 的全局量在 `main.F90:570` 解析**之后**才设置），所以锁的提示**从未到达用户**。
  ⇒ 「`persistentEnv` 与 `env` 是否同一个对象」这一点在 mctc-lib（外部依赖）里，
  **本次未读源码，标「未验证」**；可观察事实（无提示、退出码 0）是实测的。
- 上游同样如此（参照二进制 `--opt --hess` 也无提示），**不是套件引入的回归**。

### 4.5 命名一致性

| 概念 | 各任务的 flag | 判断 |
|---|---|---|
| 极小化算法 | `--lopt-engine`（`main.F90:2214`） vs `--lscan-method`（`:2279`） | **不一致**：同一概念（`landscape_opt_algorithm_from_name` 的同一 6 值集合）两个名字 |
| FD Hessian 步长 | `--lvib-step`（`:3677`）、`--lts-step`（`:2919`）、`--lirc-step-hess`（`:3597`） | **不一致**：**同一个字段** `engine%hess_step` 三个名字；且 `--lscan`/`--lopt` 完全没有 |
| SCC 精度 | `--lvib-sccacc`、`--lts-sccacc`、`--lirc-sccacc`（同一 `engine%hess_acc`） | **一致**（但 `--lopt`/`--lscan` 缺） |
| Hessian 后端 | `--{lopt,lscan,lts,lirc,lvib}-hessian` + `-hessian-file` | **一致**（语义都是 provider 选择） |
| 收敛等级 | `--lopt-level`、`--lscan-level`、`--lts-level`、`--lirc-level` | **一致** |
| 重启策略 | `--lscan-restart`、`--lts-restart`、`--lirc-restart` | **部分**（`--lopt`/`--lvib` 没有，只能用全局 `--restart/--norestart`） |
| 步数预算 | `--lscan-max-steps`、`--lts-max-steps`、`--lirc-max-steps` | **部分**（`--lopt-max-steps` 不存在） |
| 目标模式 | `--lts-target-mode`、`--lirc-target-mode` | **一致** |
| 反向开关 | `--lscan-oneway`（改 `bidirectional`）、`--lirc-oneway`（改 `both_directions`） | **一致**（字段名不同但 flag 名同构） |
| 端到端输出开关 | `--ljson` | **一致** |

**同名不同义（`-step` 一词三义、两种单位）：**

| flag | 含义 | 单位 |
|---|---|---|
| `--lscan-step` / `--lscan-step2` | 扫描坐标的**增量** | **Å（距离）/ 度（角度）** |
| `--lts-step` / `--lvib-step` | 数值 Hessian 的**有限差分位移** | bohr |
| `--lirc-step` | IRC 的**弧长**（宏步长） | **bohr·amu^½** |
| `--lirc-step-hess` | 数值 Hessian 的差分位移（= `--lts-step` 同义） | bohr |
| `--lts-step0` / `--lts-step-max` / `--lts-escape-step` | dimer 平移上限 / 上限 / 逃逸位移 | bohr |

这是「使用直觉」的核心反例：`--lscan-step` 的单位与其它三个 `-step` 不同，且 `--lirc-step`
与 `--lirc-step-hess` 只差一个后缀却是完全不同的物理量（弧长 vs 差分步长）。
另外套件内部**通篇以 bohr 为长度单位**（`settings.f90:20-22` 模块头「all lengths are in bohr」），只有 `--lscan-step` 用 Å/度
（在 `main.F90:3836-3844` 统一换算）。

**同名不同义（温度）：** `--etemp`（电子温度，原生）vs `--lvib-temp`（热化学温度表）。
两者都是 K，名字相似但作用完全不同。文档有写（`xhelp.f90:155,678`），但容易被误读。

---

## 5. CLI 测试覆盖

### 5.1 数量

- `test/unit/CMakeLists.txt` 共 **88** 个 `add_test` 调用点（其中 2 个是 foreach 模板：
  `${PROJECT_NAME}/${t}` 与 `xtb/landscape-ljson-${task}`）。
- 名字以 `xtb/` 开头的 CLI 级测试 **86** 个；其中原生 **11** 个、套件 **75** 个。
- 75 个套件 CLI 测试覆盖 5 个 runtyp（`opt/scan/vib/ts/irc`，`--ljson` 另有 `scan2d`），另有 `--ljson` 每个任务一个
  （`CMakeLists.txt:2918` `foreach(task IN ITEMS opt scan scan2d vib ts irc)`）。

统计命令：

```bash
grep -oE 'add_test\("[^"]+"' test/unit/CMakeLists.txt | sed 's/add_test("//;s/"$//' \
  | grep -c '^xtb/landscape'          # 75
```

### 5.2 flag → 有无 CLI 测试

完整对照见 §1.3 表格最后一列。汇总：

| | 数量 |
|---|---|
| 套件 flag 总数 | 122 |
| 至少被一个 CLI 测试引用的 | 64 |
| **无任何 CLI 测试引用** | **58** |

「无 CLI 测试」的 58 个：

- `--lirc-euler-n`
- `--lirc-hessian`
- `--lirc-hessian-file`
- `--lirc-mbs-max-k`
- `--lirc-mbs-points`
- `--lirc-mbs-tol`
- `--lirc-micro-cycles`
- `--lirc-micro-thresh`
- `--lirc-recalc`
- `--lirc-restart`
- `--lirc-sccacc`
- `--lirc-step-hess`
- `--lirc-target-mode`
- `--lopt-hessian-file`
- `--lscan-cold-start`
- `--lscan-expo`
- `--lscan-fc`
- `--lscan-hessian-file`
- `--lscan-oneway`
- `--lscan-restart`
- `--lts-alpha`
- `--lts-climb`
- `--lts-climb-switch`
- `--lts-dr`
- `--lts-hessian`
- `--lts-hessian-file`
- `--lts-hlow`
- `--lts-init-mode`
- `--lts-kdecay`
- `--lts-kmax`
- `--lts-kmin`
- `--lts-max-displ`
- `--lts-micro-cycles`
- `--lts-mode-overlap-min`
- `--lts-no-align`
- `--lts-no-dynamic-k`
- `--lts-no-idpp`
- `--lts-no-rigid`
- `--lts-no-string-spline`
- `--lts-recalc`
- `--lts-restart`
- `--lts-rot-alpha`
- `--lts-rot-frms`
- `--lts-rot-max-iter`
- `--lts-step-max`
- `--lts-string-grow-steps`
- `--lts-string-grow-tol`
- `--lts-string-history`
- `--lts-string-nu2`
- `--lts-target-mode`
- `--lts-translate-max-iter`
- `--lts-trust`
- `--lts-trust-max`
- `--lvib-freq-scal`
- `--lvib-no-project`
- `--lvib-rotor-cutoff`
- `--lvib-sccacc`
- `--lvib-step`

### 5.3 零引用（除 main.F90/xhelp.f90 外全仓库找不到）—— 4 个

```bash
grep -rn -- '--lts-hessian-file' . --include=*.md --include=*.f90 --include=*.cmake --include=*.py
#   → 只有 src/prog/main.F90 与 src/xhelp.f90
```

- `--lts-hessian-file`
- `--lts-micro-cycles`
- `--lts-restart`
- `--lts-trust-max`

对这 4 个我逐一确认了「读取点存在」（不是「解析后无人读」的死旋钮）：

| flag | 读取点 | 是否实测生效 |
|---|---|---|
| `--lts-hessian-file` | `src/landscape/tasks/ts.f90:216`（传给 provider） | **未验证**（未跑 `--lts-hessian file` 的 TS） |
| `--lts-micro-cycles` | `src/landscape/saddle/prfo.f90:550,718` → `bprfo.f90:134` | **部分**：`--lts-method bprfo --lts-micro-cycles 1` 与默认**能量评估数完全相同（114）**，该算例第一个 micro 循环就收敛，**无法区分是否生效** ⇒ 标「未验证」 |
| `--lts-restart` | `engine%restart_mode`（`settings.f90:331`），引擎三态策略 | **未验证**（未跑 `--lts-restart pin/warm`） |
| `--lts-trust-max` | `src/landscape/saddle/prfo.f90:479,612` | ✅ **实测生效**：`--lts-trust-max 1e-6` 使 bent HCN 在 40 步内不收敛（779 E vs 默认 95 E，`converged: F`） |

另外 5 个 flag 没有 CLI 测试但有**单元测试**引用：`--lirc-mbs-max-k`、`--lirc-mbs-tol`、
`--lirc-micro-thresh`、`--lirc-target-mode`、`--lts-no-string-spline`。

### 5.4 与既有报告的关系

`docs/_landscape-recon/46-m6-fix-report.md` §2.4 已经为 **27 个 `--lirc*`** 建立了
「选项 × 是否有测试证明生效 × 读取点」的强制表格（19 个有直接断言，8 个只有间接证据）。
本次审计是**全 122 个套件 flag** 的同构统计，结论一致：**没有发现新的死旋钮**
（3 次历史死旋钮 `engine%etemp`、`results%etemp`、`--lirc-level`/`--lirc-rmsd-end` 均已修复），
但**未覆盖的 58 个是下一次死旋钮最可能出现的地方**，其中 §5.3 的 4 个风险最高。

---

## 6. 反证：任务书 / 父会话前提中哪些是错的

### 6.1 ❌「`xhelp.f90` 里 `--l*` 顶层串只有 25 个 ⇒ 子选项可能没进 `--help`」

**错。** 实测：

- 套件在 `--help` 里的选项拼写 **122 个**，与 `main.F90` **完全一致，双向差集为 0**。
  `--lts*` 是 **56 : 56**（不是 30），一个都不缺。
- 「25 / 26」这个数字的真实含义是：`xhelp.f90` 里**不带取值的 `--l*` 布尔开关**行数：

  ```bash
  grep -oE '^ *"(--l[A-Za-z0-9-]+)(,|")' src/xhelp.f90 | wc -l    # 26
  # 其中 --lmo 与 --license 是原生 → 套件布尔开关 = 24
  ```

  也就是说，前提里的「顶层串」计数与「选项总数」是两个完全不同的量，不能用来推断覆盖率。

### 6.2 ❌「套件是对原有 CLI 的**扩展**」—— 解析层面成立，行为层面不成立

**解析层面成立**（逐条 diff 证据）：

```bash
git diff --numstat 1779020..HEAD -- src/xhelp.f90   # 416  0    ← 0 行删除
git diff --numstat 1779020..HEAD -- src/prog/main.F90  # 1978 140
```

- `main.F90` 的 140 行删除**全部是「代码搬家」**：`--metadyn` … `--nocellopt` 这一段
  （原 2025-2190）被移到套件块之后。我逐字比对了这一段与上游：
  除末尾新增的 `scan_step_user` 换算循环外**逐字相同**（`diff` 无输出）。
- `src/setparam.f90` 只**新增** 5 个 `p_run_l*` 常量（`:206,209,212,213,214`），没有改动既有值。
- `src/set_module.f90:1061-1075` 只在 `set_runtyp` 里**新增** 5 个 `case`。
- ⇒ **没有任何既有 flag 被改语义、改默认值**。

**行为层面不成立**（4 条实测差异，全部在 §3.3）：

1. `--lvib` 覆盖 `$thermo`（D5，实测）。
2. `--lscan` 默认双向 ⇒ 同 `nstep` 约 2× 成本（D4，实测 5 帧）。
3. `--lscan-fc` 默认 0.5 vs 上游 0.05（D1，实测 drift 差 3×）。
4. 输出文件名与上游**同名**（D6，实测文件清单），同目录混跑会互相覆盖
   （缓解：`--namespace`，而 `--lopt` 直到 M7 才遵守 namespace —— `docs/xtb-landscape-M7-validation.md`
   记的「4th output-naming defect」）。

因此准确表述是：**「CLI 是纯增量，默认行为不是超集」**。

### 6.3 ❌「`--ljson` 覆盖全部 6 个 run type」

`sp` 任务**没有 run type、没有 CLI**：

- `grep -c 'lsp' src/prog/main.F90` = 0；`grep -c 'lsp' src/xhelp.f90` = 0。
- `src/landscape/tasks/sp.f90` 存在且被 `src/landscape/landscape_driver.f90:83` 调用，
  但只能从 API 进（`landscape_sp_settings` 在 `main.F90` 中**从未出现**）。
- `xhelp.f90:280` 自己写明「(the sp task has no run type and is reachable through the API only)」，
  `test/unit/CMakeLists.txt:2916-2917` 也写明「The `sp` task has no run type of its own (it is API only)，
  所以由单元测试 `landscape-e2e` 的 `sp-ljson` 覆盖」。

⇒ 代码/测试/help 三方一致且诚实；「6 个」是 AGENTS.md 的松散表述，不是代码缺陷。

### 6.4 ✅ 已确认的前提

- 「runtyp 表里**没有** `p_run_scan`」：`src/setparam.f90:197-220` 确认；
  且 `--scan` 对**参照 6.7.1 二进制**也是 `Unknown option '--scan' provided`（实测）。
  上游的 relaxed scan 只能由 `--opt` + `$constrain` 的 scan 设定触发
  （`main.F90:912-914` `if (nscan > 0) call relaxed_scan(...)`，实现 `src/scan_driver.f90:21`）。
- 「`--l*` 顶层 25 个 / `--lts-*` 约 30」：**数字错**（见 §6.1），但「子选项是否都进 help」这个
  担心本身是对的（值得查），只是答案是好消息。
- 「本项目已抓到 3 次死旋钮」：与 `AGENTS.md` 记录一致（`engine%etemp`、`results%etemp`、
  `--lirc-level`/`--lirc-rmsd-end`）；本次在**套件侧未发现第 4 个**，但在**原生侧**发现
  `xhelp.f90` 的 3 个「已文档化未实现」选项，以及在 `AGENTS.md:130` 发现 1 个虚构套件选项
  （`--lts-printlevel`）。

---

## 7. 局限与未验证项（如实列出）

1. `persistentEnv` 与 `src/prog/primary.f90:38` 的 `env` 是否同一对象 —— 未读 mctc-lib 源码
   （外部 FetchContent 依赖，位于父会话构建目录内，按纪律未读取）。可观察结论（锁提示不显示）是实测的。
2. `$thermo scale=0.9` 让 `--hess` 的 VIB 焓变成 1.9× 的机制 —— 未追根因（属上游 `print_thermo`）。
3. `--lts-hessian-file`、`--lts-restart`、`--lts-micro-cycles` 的「是否真的改变结果」——
   前两个未跑，第三个跑了但算例无法区分 ⇒ 全部标「未验证」。
4. `--lirc-euler-n`、`--lirc-mbs-points`、`--lirc-recalc` 等只有间接证据 —— 沿用报告 46 §2.4 的判断，
   本次未复测。
5. 原生参数的默认值未与上游逐条比对（`main.F90` 既有 case 体逐字未变，且 `xhelp.f90` 0 行删除，
   故推定原生默认值未变；**这是推定，不是逐条实测**）。
6. `--cycles [int]`（原生，`xhelp.f90:690`）与 `main.F90:1918` 的语义对照未做（**未验证**）。
7. 未运行 `ctest`（按纪律不跑全量、也不动父会话构建目录），§5 的测试数全部由
   `test/unit/CMakeLists.txt` 静态统计得出，未在运行态核对 `ctest -N` 的展开结果
   （foreach 模板的实际展开数量是按 `CMakeLists.txt:2918` 的 6 个 task 手工推得）。

---

## 8. 给父会话的建议（不含新决策，只是事实指向）

1. **`--lvib` 覆盖 `$thermo`**（§2.5）是本次唯一「文档承诺与行为不符且会影响数值」的套件缺陷，
   建议优先处置；影响面：任何用 `$thermo temp=` 多温度表或 `scale=` 的用户。
2. `--lopt-max-steps` 缺失、`--lopt-engine` vs `--lscan-method` 命名分裂、`-step` 一词三义
   —— 属于「使用直觉」层面的欠账，是否需要统一是新决策，本次不代为决定。
3. `--lts-printlevel` 在 `AGENTS.md:130` 是**纯文字错误**（该 flag 不存在），修文档即可。
4. `--lscan` 的三个必填参数报错不点 flag 名 —— 与 M4 的「可操作诊断」约定不一致，是一处小缺口。
