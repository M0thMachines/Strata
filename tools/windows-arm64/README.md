# Windows on Arm (ARM64) + NVIDIA Blackwell port

Native `windows-arm64` build of Strata for the NVIDIA N1X platform (Blackwell, `sm_120`).
Everything in the resulting runtime is native ARM64 — engine, CUDA kernels, cuBLAS,
quantization paths, Node host, gateway, GUI shell. No emulation.

## Build (performed on the N1X rig itself)

Toolchain: VS Build Tools 2022 (arm64), CUDA 13.5 `windows-arm64` redist packages
(assembled into a flat toolkit root; add `libnvvm` so `cicc` is present), LLVM `clang-cl`
for C/C++ (MSVC `cl` does not accept the ARM NEON/dotprod quant intrinsics), native
MSVC `Hostarm64/arm64/cl.exe` as `CMAKE_CUDA_HOST_COMPILER`, `Ninja Multi-Config`.

```
cmake -G "Ninja Multi-Config" -S engine -B engine-build ^
  -DSTRATA_ENABLE_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=120 ^
  -DCUDAToolkit_ROOT=<cuda-root> -DCMAKE_CUDA_COMPILER=<cuda-root>/bin/nvcc.exe ^
  -DCMAKE_C_COMPILER=<llvm>/bin/clang-cl.exe -DCMAKE_CXX_COMPILER=<llvm>/bin/clang-cl.exe ^
  -DCMAKE_CUDA_HOST_COMPILER="<vsbuildtools>/VC/Tools/MSVC/<ver>/bin/Hostarm64/arm64/cl.exe"
cmake --build engine-build --config Release -j 8
```

Vision: same pattern from `terminal/tools/vision` with `-DSTRATA_VISION_CUDA=ON`.

## Port patches in this branch

- `engine/src/kernels/cpu/expert_layout.cpp` — x86 `<immintrin.h>` include was gated on
  bare `_MSC_VER`; clang-cl defines `_MSC_VER` on ARM too. Gated to `_M_X64 || _M_IX86`.
- `engine/src/program/generate.cpp` — crash-dumper backtrace used x64 `CONTEXT.Rip/Rsp`;
  now arch-neutral `STRATA_CTX_PC/SP` (`Pc/Sp` on ARM64).
- `app/desktop/src-tauri/tauri.conf.json` — bundle resources trimmed: the vendor x64
  sidecars (`resources/node|control|harness|engine-bundle`) do not exist on WoA; package
  the native host UI/server instead (`tauri build --no-bundle` + runtime layout below).

## Native OpenAI endpoint (`gateway.mjs`)

The engine `--serve` speaks line-JSON over stdio, not HTTP. `gateway.mjs` (zero-dependency
Node, runs on arm64 Node) exposes OpenAI-compatible `POST /v1/chat/completions`
(stream + non-stream), `GET /v1/models`, `GET /v1/status`, `GET /metrics` on :18500 and
bridges to the engine, with its own Qwen tokenizer built from the pack tokenizer files
(`vocab.json`, `merges.txt`, `tokenizer.json`; watch for CRLF in `merges.txt`).
Run via `scripts/gateway-run.cmd` / `gateway-start.cmd`; engine flags go after `--`.

## GUI runtime layout (no installer bundle)

The unbundled `strata-desktop.exe` resolves resources next to itself: place
`host/` (with `server/index.mjs`, `dist/`) and `node/` (native arm64 `node.exe`)
as siblings of the exe — the installer in `installer/` does exactly that.
Control (Python) is optional: `control/python/python.exe` embedded arm64 +
`strata.py` + `strata_control/`; psutil has no Windows-arm64 wheel and is skipped
(source guards the import).

## Installers

`installer/` builds both formats with WiX v6 (`dotnet build Bundle.wixproj`, and
`wix build Product.wxs -arch arm64`): an arm64 `.msi` and a Burn `.exe` bundle that
embeds it. Verified end-to-end on the N1X rig: silent install, native gateway serving
chat completions from the installed tree.
