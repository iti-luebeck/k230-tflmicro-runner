# K230 TFLM Runner

Build and measurement harness for running [MLPerf Tiny](https://github.com/mlcommons/tiny)
benchmarks on the [Kendryte K230](https://www.kendryte.com/k230/en/dev/) with
TensorFlow Lite Micro, comparing scalar RISC-V against hand-written RISC-V Vector
(RVV) kernels.

This is the reproduction artifact for:

> **_TinyML Unleashed: Accelerating TensorFlow Lite Micro Kernels with RISC-V Vector Extension_**
> A. Mahmoudi, C. Horn, S. Mulhem, R. Buchty, M. Berekovic, R. Meyer.
> 2025 33rd Telecommunications Forum (TELFOR), 2025, pp. 1–4.
> DOI: [10.1109/TELFOR67910.2025.11314213](https://doi.org/10.1109/TELFOR67910.2025.11314213)

The RVV kernels themselves live in the
[`tflite-micro-rvv`](https://github.com/iti-luebeck/tflite-micro-rvv) submodule.
They are generic `rv64imafdcv` code and are **not** K230-specific — this repository is the K230
instantiation plus the measurement harness.

## Results

Measured on the K230 big core at 1.6 GHz. Three build configurations are compared:

- **Scalar** — reference TFLM kernels, built for `rv64imafdc` (no vector extension)
- **Auto** — same sources built for `rv64imafdcv`, relying on compiler auto-vectorization
- **Manual** — the hand-written RVV kernels in the `tflite-micro` submodule

| Model | Implementation | CPI | Latency (ms) | Throughput (IPS) | Speed-up |
|---|---|---:|---:|---:|---:|
| **ResNet** (Image Classification) | Scalar | 1.27 | 484.5 | 2.06 <sup>†</sup> | 1× |
| | Auto | 1.11 | 423.8 | 2.36 | 1.14× |
| | **Manual** | 2.01 | **16.9** | **59.21** | **28.69×** |
| **FC-AutoEncoder** (Anomaly Detection) | Scalar | 1.21 | 1.93 | 517.76 | 1× |
| | Auto | 0.97 | 0.59 | 1680 | 3.24× |
| | **Manual** | 2.30 | **0.47** | **2133** | **4.12×** |
| **MobileNetV1** (Person Detection) | Scalar | 1.25 | 321.5 | 3.11 | 1× |
| | Auto | 1.09 | 283.0 | 3.53 | 1.14× |
| | **Manual** | 1.18 | **48.5** | **20.61** | **6.62×** |
| **DS-CNN** (Keyword Spotting) | Scalar | 1.23 | 112.9 | 8.92 | 1× |
| | Auto | 1.09 | 100.8 | 9.92 | 1.11× |
| | **Manual** | 1.15 | **16.6** | **60.5** | **6.80×** |

Hand-written RVV kernels outperform compiler auto-vectorization in every case, by
between 1.3× (FC-AutoEncoder) and 25× (ResNet). Auto-vectorization alone yields
only 1.11×–1.14× on the convolutional models.

CPI rises for the manual kernels on ResNet and FC-AutoEncoder because vector
instructions retire more slowly while doing far more work per instruction —
latency and throughput are the meaningful comparison, not CPI.

<sup>†</sup> **Corrected.** The published table lists 1.21 IPS here, which is
inconsistent with the same row's latency of 484.5 ms — the measurement harness
derives throughput as `1e6 / latency_us`, so 484.5 ms necessarily gives 2.06 IPS.
The ResNet speed-ups are recomputed from the corrected value (published: 1.15×
and 28.75×; both were ~0.3% high). All other figures are as published.

## Repository layout

```
build_script_tflite.sh   interactive build driver (compile + link + deploy)
tflite-micro/            submodule - TFLM fork with the RVV kernels
k230_sdk/                submodule - Canaan K230 SDK (toolchain, linker scripts)
```

Expected working layout once toolchains are unpacked:

```
k230_sdk/
    |-- src/big/mpp/userapps/sample/linker_scripts/riscv64/link.lds
tflite-micro/
    |-- tensorflow/lite/micro/examples/mlperf_riscv_image_classification/
    |-- tensorflow/lite/micro/examples/mlperf_riscv_person_detection/
    |-- tensorflow/lite/micro/examples/mlperf_riscv_keyword_spotting/
    |-- tensorflow/lite/micro/examples/mlperf_riscv_anomaly_detection/
    |-- tensorflow/lite/micro/tools/make/targets/
            |-- riscv_isa_elf_rv64imafdc_makefile.inc
            |-- riscv_isa_elf_rv64imafdcv_makefile.inc
            |-- riscv_isa_musl_rv64imafdc_makefile.inc
            |-- riscv_isa_musl_rv64imafdcv_makefile.inc
toolchain/
    |-- riscv_elf/bin/       riscv64-unknown-elf-gcc
    |-- riscv_musl/bin/      riscv64-unknown-linux-musl-gcc
```

## Prerequisites

- Kendryte K230 board, with a serial console and network access
- A Linux host with `make`, `bash`, and `scp`
- RISC-V GNU toolchains (ELF and musl variants) — fetched by `build_script_tflite.sh`
- The Canaan proprietary toolchain from the K230 SDK, used for the final link step
  (binary distribution only)

## Getting started

```bash
git clone --recurse-submodules <this-repo>
cd k230-tflmicro-runner
./build_script_tflite.sh
```

The script prompts for a benchmark and a toolchain, then compiles, links, and
reports the resulting ELF. Run it with no arguments for the interactive menu.

## Build workflow

`build_script_tflite.sh` automates a two-stage process, because the K230 big core
requires linking with the Canaan toolchain even when compilation uses the RISC-V
GNU toolchain.

**Toolchain options**

| Toolchain | Compiler | Separate link step? |
|---|---|---|
| GNU (ELF), no V extension | `riscv64-unknown-elf-gcc` | No |
| musl, with or without V extension | `riscv64-unknown-linux-musl-gcc` | Yes — Canaan toolchain |

**Stages**

1. **Compile** — runs the TFLM Makefile with the matching `TARGET`, e.g.
   `riscv_isa_musl_rv64imafdcv` (vector) or `riscv_isa_musl_rv64imafdc` (scalar).
2. **Link** (musl only) — combines the `.o` files with the Canaan toolchain.
   `hexdump_test.o` is excluded: it carries its own `main()` and exists only for
   TFLM compilation tests.
3. **Deploy** — `scp` the ELF to the board, then run it over the serial console.

**Link flags** — the ABI and code model must match across both toolchains:

```
# with V extension
-mcmodel=medany -march=rv64imafdcv -mabi=lp64d
# without V extension
-mcmodel=medany -march=rv64imafdc  -mabi=lp64d
```

Mixing a GNU-compiled object set with the Canaan linker works as long as these are
passed consistently.

**Running on the board**

```bash
scp <benchmark>_<target>.elf root@<board-ip>:/root/
screen /dev/ttyAMC1 115200
```

## Toolchain integration notes

Non-obvious settings, all in
`tflite-micro/tensorflow/lite/micro/tools/make/targets/riscv_isa_musl_rv64imafdcv_makefile.inc`:

```make
TARGET_ARCH := riscv64
TARGET_TOOLCHAIN_PREFIX := riscv64-unknown-linux-musl-

RISCV_ARCH := rv64imafdcv     # drop the trailing 'v' to disable RVV
RISCV_ABI := lp64d
RISCV_CODE_MODEL := medany

# Selects the hand-written RVV kernels
OPTIMIZED_KERNEL_DIR := riscv_vector

# Big core: enables rdcycle-based timestamping in submitter_implemented.cc
RISCV_EXTRA_CFLAGS += -DBIG_CORE -D__riscv_vector

# Linker relaxation produced incorrect code on this target
LDFLAGS += -mno-relax
```

Two further gotchas:

- `memory_arena_threshold_test.cc` is excluded from the test sources
  (see upstream `b/158651472`).
- For the scalar build, strip the RISC-V attributes section before deploying, or
  the Canaan loader rejects the binary:

  ```bash
  riscv64-unknown-linux-musl-strip --remove-section=.riscv.attributes <binary>.elf
  ```

## SD card image

The bootable image (Linux on the small core, RT on the big core) is **not
distributed here** — it is built from the pinned `k230_sdk` submodule, and
redistributing a prebuilt image would carry the SDK's own licensing obligations
for its GPL and proprietary components.

Build it from the SDK following Canaan's
[environment preparation guide](https://www.kendryte.com/k230/en/dev/02_applications/tutorials/K230_Practical_Basics_hello_world.html#environment-preparation),
then flash the resulting `sysimage-sdcard.img` to the card.

## Measurement methodology

Cycles and retired instructions are read directly from the RISC-V counters on the
big core (1.6 GHz; the small core runs at 800 MHz):

```c
uint64_t perf_get_smodecycles(void) {
    uint64_t cnt;
    __asm__ __volatile__("rdcycle %0" : "=r"(cnt));
    return cnt;
}
```

`rdinstret` is read the same way for the instruction count. Derived figures:

```c
uint64_t cycle_count = end_cycles - start_cycles;
double cycle_count_per_infer = (double)cycle_count / (double)total_inferences;
uint64_t instret_count = end_instret - start_instret;
double cpi = (double)cycle_count / (double)instret_count;
unsigned long runtime_us = end_time - start_time;
double runtime_sec = (double)runtime_us / 1e6;
double latency_us = (double)runtime_us / (double)total_inferences;
double throughput = 1e6 / latency_us;   // inferences per second
```

Each run emits `m-cycles-count`, `m-instret-count`, `m-cycles-count-per-infer`,
`m-cycles-per-instructions`, `m-runtime-us`, `m-latency-us`, and
`m-throughput-IPS` over the serial console.

To confirm which kernels a build actually uses, `objdump` the ELF and look for
vector instructions (`vmv.*`, `vadd.vv`, `vsub.vv`).

## License

Licensed under the Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Bundled components keep their own licences:

| Component | Licence |
|---|---|
| [`tflite-micro`](https://github.com/iti-luebeck/tflite-micro-rvv) (submodule) — fork of [tensorflow/tflite-micro](https://github.com/tensorflow/tflite-micro) | Apache 2.0 |
| [`k230_sdk`](https://github.com/kendryte/k230_sdk) (submodule) — Canaan Creative | BSD 2-Clause |

Note that images **built from** the K230 SDK bundle further third-party
components under their own terms, including the Linux kernel and U-Boot
(GPL-2.0). No such image is redistributed here — see
[SD card image](#sd-card-image) for how to build one.

## Citation

```bibtex
@INPROCEEDINGS{11314213,
  author={Mahmoudi, Ahmed and Horn, Christopher and Mulhem, Saleh and Buchty, Rainer and Berekovic, Mladen and Meyer, Rolf},
  booktitle={2025 33rd Telecommunications Forum (TELFOR)},
  title={TinyML Unleashed: Accelerating TensorFlow Lite Micro Kernels with RISC-V Vector Extension},
  year={2025},
  pages={1-4},
  doi={10.1109/TELFOR67910.2025.11314213}}
```
