# GAP-05a 性能

日期 2026-10-23。机器 Linux WSL2，SBCL 2.6.7，默认动态堆 1GB（`dynamic_space_size` 1073741824）。Node 对照是本机 Node v22.22.0，包 `quickjs-wasi@3.6.2`，wasm 与钉死的 SHA-256 `d4c9375f2b1ca4dc95f72c8aa2982a7a9951ac8011490d79c6582df732b4bbd9` 相同。计时用 `get-internal-real-time`，本镜像 `internal-time-units-per-second` 是 1000，所以 0ms 表示不到 1ms。

上游 v1.4.0 `packages/codemode/src/runtime/host.ts` 每次执行新建一个 worker 和一份 QuickJS VM。`packages/codemode/src/wasm.ts` 的 `loadQuickJSWasm` 对同一个路径只 `WebAssembly.compile` 一次。cadr 复用的是 AOT 模块，每次 `codemode-make-vm` 新建实例。`fresh-quickjs-instances-do-not-share-globals` 锁住：一个实例里写下的全局，下一个实例读到的是 undefined。

## 阶段

默认堆，模块已经在进程里。

| 阶段 | 时间 |
|---|---|
| `instantiate` | <1ms |
| `_initialize` | <1ms |
| `qjs_init` | 4ms |
| 线性内存（init 之后） | 1376256 字节 |
| 这一次实例的 RSS 增量 | 5832 kB |
| 求值 `1+1` | <1ms，值 2 |
| 求值 prelude 源码 | 16ms |
| `codemode-run-vm` `"return 1 + 1;"` 第一次 | 264ms，值 2 |
| 同进程第二次、第三次 | 128ms、128ms，值 2 |

128ms 和 264ms 含 prelude 的 lockdown、桥和 `(async (tools, console) => { return 1 + 1 })`。实例化不是这 128ms 的来源。单次实例 RSS 5832 kB，低于 300MB。第一次 264ms，低于 2s。后续 128ms，低于 200ms。

优化前同路径的后续执行是 1026ms 和 953ms。当时 prelude 调用约 928ms，`qjs_init` 约 20ms，实例化仍然不到 1ms。

## 剖析

优化前，sb-sprof 对 prelude 调用采样 213 次、0.213s。自身时间靠前的是 `LOAD-LE`（9.4%）、带边界检查的泛型向量读（8.5%）、`MEM-RANGE`（7.0%）、`ASH`（4.7%）、`I32`（4.2%）、`I32-ADD`（3.3%）。i64 走大整数。

优化后，对 1e6 次 `s+=i` 采样 73 次、0.073s。前 20 里有计数的是：

| 自身 | 函数 |
|---|---|
| 31.5% | 生成的 7 参 lambda（quickjs-aot） |
| 16.4% | `VECTOR-HAIRY-DATA-VECTOR-REF` |
| 8.2% | `arch_set_fp_modes` |
| 6.8% | 另一个生成 lambda |
| 5.5% | 两个生成 lambda，各 5.5% |
| 5.5% | `(OPTIMIZED-DATA-VECTOR-REF T)` |
| 4.1% | `pthread_sigmask` |
| 2.7% | `arch_get_fp_modes` |
| 2.7% | `F64-TO-BITS` |
| 1.4% | 又一个生成 lambda、`I64`、`I64-EXTEND32-S` |

`s+=i` 在 QuickJS 里是 f64，不是 i32。浮点陷阱屏蔽出现在每次 f64 运算上。

后续 `return 1 + 1` 的一次采样（49 次，当时另一份 SBCL 在编译 spec 夹具，墙钟偏高；安静时墙钟是上面的 128ms）里，自身时间靠前的是泛型向量读 12.2%、T 向量读 8.2%、那个 7 参 lambda 6.1%、`SHA256-HEX` 6.1%（总时间 18.4%，来自每次执行都重新解码并哈希 wasm）。哈希已经从后续执行拿掉，见下面的优化。宿主侧 worker 和序列化不在这 128ms 里：这次调用停在 `codemode-run-vm`，没有走工具队列。

## 吞吐

同一段脚本。Node 用 `QuickJS.create({ wasm })` 然后 `evalCode`，时间不含建 VM。cadr 在已经 `qjs_init` 的实例上 `qjs_eval`。

| 脚本 | cadr | Node 22.22.0 | 倍数 |
|---|---|---|---|
| `let s=0; for (let i=0;i<1000000;i++) s+=i; s` | 1584ms，值 499999500000 | 第二次 78.5ms（第一次 106.2ms），值相同 | 20.2 |
| 1MB `"x"` 的 `JSON.stringify(JSON.parse(JSON.stringify(s))).length` | 540ms，值 1048578 | 33.2ms，值 1048578 | 16.3 |

cadr 的 JSON 脚本用 `var`，Node 用 `const`。两边结果都是 1048578。倍数目标是 ≤ 5。两个都超过。

一段手写的 i32 加法循环（1e7 次）在小函数上是 20–24ms。大函数没有落到这个速度：1e6 次 JS 加法仍要 1.6s。

## 构建期 AOT

`scripts/aot-quickjs-wasm.sh`，SBCL 2.6.7，`--dynamic-space-size 8192`。

| | 墙钟 | 峰值 RSS | fasl |
|---|---|---|---|
| 优化前 | 3:53.13 | 1334684 kB | 17821575 字节 |
| 这次（speed 3, safety 0, debug 0） | 6:44.89 | 2346916 kB | 13873765 字节 |

运行期 `ensure-compiled` 对这份摘要不调用 `compile-module`。默认堆加载 fasl。

## 做过的优化

- 数值函数（参数、结果、局部变量和调用目标都不是 funcref/externref）生成 `(unsigned-byte 64)` 词法变量和操作数栈，i32/i64 加减乘、位运算、比较、移位、load/store 内联。内存是 `(simple-array (unsigned-byte 8) (*))`，边界检查显式做一次。没有用 sap：内存会在 `memory.grow` 时换成新数组，移动式 GC 也不能把 sap 留在函数里。
- 这些函数在 `(optimize (speed 3) (safety 0) (debug 0))` 下编译。局部变量加上参数超过 64 个时改回 `(speed 1) (safety 1) (compilation-speed 3)`。`skip-stack-guard-page` 有约 1000 个 i64 局部变量，全速度编译会把 SBCL 的控制栈打爆。quickjs 这份 wasm 的函数不超过这个上限。
- 加上 `(compilation-speed 3)` 再整模块重编，1e6 循环是 1476ms，和全速度的 1584ms 同一量级。保留全速度。
- `quickjs-wasm-bytes` 只解码一次。后续 `ensure-compiled` 看到同一向量就不再做 SHA-256。这把安静时的后续 `return 1 + 1` 从大约 300ms（和另一份编译抢 CPU 时）收到 128ms。
- 没有做初始化后快照。上游每次执行都是新 VM，快照不能省掉 prelude。

## 冷启动

`scripts/goal11-cold-start.py` 原先等连续的 `cadr v`。启动帧把这个词换成半块 logo（`src/cadr-cli/interactive/components/pi-logo.lisp`），版本号还在，形式是 `v<major>.<minor>.<patch>`。另外，二进制放在本仓库里时，工作目录就是仓库，全新 `HOME` 会先停在 `Trust project resources ...? [y/N]`，帧根本不会画。脚本改为在那个空 `HOME` 里启动，并等版本号。

2026-10-23，各三次，单位是微秒：

| 镜像 | 字节 | 三次 |
|---|---|---|
| 含这份 AOT | 26362224 | 459328、473335、424729 |
| 不含 cadr-wasm | 23015056 | 477882、429179、422526 |

差值 3347168 字节。两边都在 425–478ms，750ms 以内。AOT 没有把冷启动拉过线。

## 5''''' 这一轮

五处改动一次落在翻译器里，然后整份 quickjs wasm 重做了一次 AOT。没有按项各编一份镜像，所以下面的 quickjs 数字是合并后的，对照是上面那一节。

翻译器现在的热路径：

- 进入 `invoke` 时屏蔽一次浮点陷阱。生成的函数体里没有逐条 `with-float-traps-masked`。
- f32/f64 的局部变量、操作数栈和全局用 `single-float` / `double-float`。加减乘除和比较在类型化的值上内联，NaN 仍收成规范 NaN。位型转换只在函数边界、load/store 和 reinterpret，用 `sb-kernel:make-double-float` 和高低位读取。
- 线性内存在函数入口取进一个 `(simple-array (unsigned-byte 8) (*))` 局部变量，`memory.grow` 和调用之后再取。没有用 sap。
- 实例的函数、内存、表、全局是 `simple-vector`。AOT 里模块函数互相按名字调用，不走 `apply`。间接调用做一次签名检查，然后按已知参数个数 `funcall`。
- 局部变量加参数超过 64，或函数体超过 400 条指令的冷函数，不展开成几千条 `aref`。`skip-stack-guard-page` 走一个小循环解释器，默认堆能译完。

AOT：`scripts/aot-quickjs-wasm.sh`，SBCL 2.6.7，`--dynamic-space-size 8192`。墙钟 4:33.98，峰值 RSS 2432324 kB，fasl 12113280 字节。上一轮是 6:44.89、2346916 kB、13873765 字节。

吞吐仍是已经 `qjs_init` 的实例上只计 `qjs_eval`。每次求值用新实例，和 Node 每次 `QuickJS.create` 再计 `evalCode` 一样。`internal-time-units-per-second` 这次是 1000000。Node 对照同一天重跑了 `/tmp/qjs-bench/bench.mjs`。

| 脚本 | cadr | Node 22.22.0 | 倍数 |
|---|---|---|---|
| `let s=0; for (let i=0;i<1000000;i++) s+=i; s` | 708ms、696ms，值 499999500000 | 第一次 100.3ms，第二次 65.3ms，值相同 | 10.7 |
| 1MB `"x"` 的 `JSON.stringify(JSON.parse(JSON.stringify(s))).length` | 304ms，值 1048578 | 31.7ms，值 1048578 | 9.6 |

`qjs_eval` 的 `1+1` 不到 1ms，值 2。上一轮 1e6 循环是 1584ms（20.2 倍），JSON 是 540ms（16.3 倍）。这一轮短了，仍超过 5 倍。

1e6 循环的 `sb-ext:get-bytes-consed` 差值是 794657984 字节。热循环还在分配。f64 的绝对值不小于 1 时，位型的第 62 位是 1，跨函数传递的 `(unsigned-byte 64)` 是大整数。

sb-sprof，174 个样本，0.174s。自身时间靠前的是：

| 自身 | 函数 |
|---|---|
| 53.4% | `QJS-AOT-80` |
| 11.5% | `QJS-AOT-87` |
| 8.0% | `pthread_sigmask` |
| 4.6% | `QJS-AOT-27` |
| 4.6% | `QJS-AOT-28` |
| 4.6% | `QJS-AOT-81` |
| 2.9% | `QJS-AOT-97` |
| 1.1% | `ALLOC-UNSIGNED-BIGNUM-IN-RDI` |

`arch_set_fp_modes` 和 `arch_get_fp_modes` 不在采样里。`VECTOR-HAIRY-DATA-VECTOR-REF` 和 `(OPTIMIZED-DATA-VECTOR-REF T)` 也不在。`pthread_sigmask` 的总时间挂在 `interrupt_handle_pending` / `maybe_gc` 下面，不是每条浮点运算各屏蔽一次。`lisp_alloc` 的总时间是 8.6%。生成的 quickjs 源里没有 `with-float-traps-masked`。

热函数自身占一半以上，剩下的大头是别的已编译 quickjs 函数。再去掉陷阱屏蔽和泛型向量读，补不上到 5 倍以内的那一截。
