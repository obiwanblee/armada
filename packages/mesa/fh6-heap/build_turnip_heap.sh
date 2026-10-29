#!/usr/bin/bash
set -euxo pipefail
dnf -y install 'dnf-command(builddep)' curl patch git
dnf -y builddep mesa
cd /work
curl --fail --location --retry 3 --silent --show-error -o mesa-26.2.4.tar.xz https://archive.mesa3d.org/mesa-26.2.4.tar.xz
echo 'bce5f7fbebb934373b86c999a064d52fb5065878dc57f287f95346648ec832e9  mesa-26.2.4.tar.xz' | sha256sum --check --strict
mkdir src
tar xf mesa-26.2.4.tar.xz -C src --strip-components=1
for p in /work/patches/*.patch; do patch -d src -p1 --forward --no-backup-if-mismatch < "$p"; done
# Keep the untested X1-85 gated, matching the newer RFC's hardware scope.
python3 - <<'PY'
from pathlib import Path
p=Path('src/src/freedreno/common/freedreno_devices.py')
s=p.read_text(); needle='        GPUId(chip_id=0xffff43050c01, name="Adreno X1-85"),'
assert s.count(needle)==1
pos=s.index(needle); start=s.rfind('add_gpus([',0,pos); end=s.index('    ))',pos)+len('    ))')
block=s[start:end]
assert 'GPUProps(supports_sparse_image_2d = True)' in block
original=block.replace(needle+'\n','')
body=block[block.index('    ], A6xxGPUInfo('):].replace(', GPUProps(supports_sparse_image_2d = True)','')
x1='add_gpus([\n'+needle+'\n'+body
s=s[:start]+original+'\n\n'+x1+s[end:];p.write_text(s)
PY
CFLAGS='-O2 -march=armv8.2-a+fp16+dotprod+i8mm -mtune=cortex-a78' \
CXXFLAGS='-O2 -march=armv8.2-a+fp16+dotprod+i8mm -mtune=cortex-a78' \
meson setup src/build src --buildtype release --prefix /usr \
  -Dgallium-drivers= -Dvulkan-drivers=freedreno -Dfreedreno-kmds=msm \
  -Dplatforms=x11,wayland -Dglx=disabled -Degl=disabled -Dgbm=disabled \
  -Dopengl=false -Dllvm=disabled -Dbuild-tests=true -Dtu-build-id=fh6-a740-heap3
ninja -C src/build -j"$(nproc)"
meson test -C src/build --print-errorlogs fd6_layout
install -D -m 0755 src/build/src/freedreno/vulkan/libvulkan_freedreno.so /work/out/libvulkan_freedreno.so
cp src/build/src/freedreno/vulkan/freedreno_icd.aarch64.json /work/out/
sha256sum /work/out/libvulkan_freedreno.so
echo BUILD_OK
