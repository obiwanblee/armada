# fh6-heap: Astra's fh6-sparse1 Turnip + process-wide heap usage

Reproduces the live `fh6-sparse1` driver (Mesa 26.2.4 + patches 0001/0002/0003/0005,
Astra's `~/fh6diag-20261027-sparse1/build_turnip_sparse.sh`, verified sha
2a93bbe7395ec2e13ac31b3822123a4fb7c6adfa13a707e25961ee6af0fb3360) and adds
`0006-tu-process-wide-heap-usage.patch`, a port of DroidDeck Drivers'
`patches/scripts/process_heap_usage.py` onto 26.2.4: `VK_EXT_memory_budget`
heapUsage[0] becomes a process-wide counter so DXVK's DXGI instance reports
vkd3d-proton's allocations to Forza Horizon 6 (which shows 0 KB video memory and
streams until failure on sparse1). Built by `.github/workflows/fh6-heap.yml`.
