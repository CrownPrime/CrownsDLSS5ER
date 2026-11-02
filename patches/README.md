# Source changes

## OptiScaler (GPL-3.0): `crownsdlss5er-optiscaler-v0.8.10.patch`

The release ships a modified build of the OptiScaler DLSS-NR fork. Under GPL-3.0, its complete source is
available here.

- **Base:** [wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass](https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass),
  tag `v0.8.10` (commit `6125a75b37f7e2a408e31934f4827e5660429203`).
- **Changes:** three files, `OptiScaler/menu/menu_common.cpp`, `OptiScaler/dlssnr/DlssNr_PipelineUi.h` and
  `OptiScaler/dlssnr/DlssNr_Menu.cpp`. They add:
  - a CrownsDLSS5ER header with the emblem drawn as ImGui shapes;
  - the window title;
  - theme colour defaults;
  - gold in place of green in the DLSS-NR panel.

**To build it yourself:**

```
git clone https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass.git
cd OptiScaler-DLSSNR-PreSR-Multipass
git checkout v0.8.10
git submodule update --init --depth 1
git apply path\to\crownsdlss5er-optiscaler-v0.8.10.patch
msbuild OptiScaler.sln /t:OptiScaler /p:Configuration=Release /p:Platform=x64
```

That needs Visual Studio 2022 with the C++ tools (toolset v143).

The same change is committed, ready to clone and build, on the public fork:
**[CrownPrime/OptiScaler-DLSSNR-PreSR-Multipass @ `crownsdlss5er`](https://github.com/CrownPrime/OptiScaler-DLSSNR-PreSR-Multipass/tree/crownsdlss5er)** (commit `d12b49c5`).

## EldenRingDLSS (MIT): `EldenRingDLSS-0.1.0-crownsdlss5er.patch`

- **Base:** [masonpetrosky/EldenRingDLSS](https://github.com/masonpetrosky/EldenRingDLSS) v0.1.0. Apply the patch to
  its `src/` folder and build with its `build.ps1`.
- **Changes:**
  - **Device rebinding:** if the D3D12 device DLSS was set up on is destroyed (for example a short-lived
    integrated-GPU device), the add-on moves to the remaining device.
  - **ReShade proxy objects for NGX:** NGX gets ReShade's proxy command list, and is re-initialised on that list's
    device. This fixes a crash in `D3D12Core!SetDescriptorHeapsInternal` when the DLSS-NR model records into the
    unwrapped list.
  - **Toggle while upscaling:** switching DLSS back on (F9 or the overlay) below native rebuilds the DLSS feature,
    so the engine scales down again instead of staying on the game's TAA.
  - **Loading screens and cutscenes while upscaling:** when the engine has gone back to full size, the add-on
    rebuilds the DLSS feature itself (at most every 300 frames), so DLSS resumes without pressing F9.
