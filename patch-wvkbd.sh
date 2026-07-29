#!/bin/bash
# Patch wvkbd for the AYN Thor:
#  (1) inject keystrokes via /dev/uinput (KWin has no wlr virtual-keyboard)
#  (2) pin the keyboard to a chosen output by connector name (-O DSI-1)
set -euo pipefail
cd wvkbd

# ---- (1) uinput injection shim ----
cat > /tmp/wvkbd-uinput-shim.h <<'SHIM'
/* --- Armada/Thor uinput injection shim (KWin lacks wlr virtual-keyboard) --- */
#include <linux/uinput.h>
#include <linux/input-event-codes.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static int wvkbd_uifd = -1;
__attribute__((constructor)) static void wvkbd_uinput_init(void) {
  wvkbd_uifd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
  if (wvkbd_uifd < 0) { perror("wvkbd: /dev/uinput"); return; }
  ioctl(wvkbd_uifd, UI_SET_EVBIT, EV_KEY);
  ioctl(wvkbd_uifd, UI_SET_EVBIT, EV_SYN);
  for (int i = 1; i < 256; i++) ioctl(wvkbd_uifd, UI_SET_KEYBIT, i);
  struct uinput_user_dev uud;
  memset(&uud, 0, sizeof(uud));
  snprintf(uud.name, sizeof(uud.name), "wvkbd-uinput");
  uud.id.bustype = BUS_USB; uud.id.vendor = 0x1209;
  uud.id.product = 0xb07f; uud.id.version = 1;
  if (write(wvkbd_uifd, &uud, sizeof(uud)) < 0) perror("wvkbd: uinput setup");
  ioctl(wvkbd_uifd, UI_DEV_CREATE);
}
static void wvkbd_uinput_key(uint32_t code, int state) {
  if (wvkbd_uifd < 0) return;
  struct input_event ev[2];
  memset(ev, 0, sizeof(ev));
  ev[0].type = EV_KEY; ev[0].code = (uint16_t)code; ev[0].value = state ? 1 : 0;
  ev[1].type = EV_SYN; ev[1].code = SYN_REPORT; ev[1].value = 0;
  if (write(wvkbd_uifd, ev, sizeof(ev)) < 0) { /* ignore */ }
}
#define zwp_virtual_keyboard_v1_key(vk, t, code, st) wvkbd_uinput_key((code), (st))
#define zwp_virtual_keyboard_v1_modifiers(vk, d, l, lo, g) ((void)0)
#define zwp_virtual_keyboard_v1_keymap(vk, fmt, fd, sz) ((void)0)
/* --- end shim --- */
SHIM
sed -i '/#include KEYMAP/r /tmp/wvkbd-uinput-shim.h' keyboard.c
sed -i 's/if (kb->vkbd == NULL) {/if (0) {/' keyboard.c
sed -i 's/if (vkbd_mgr == NULL) {/if (0) { \/* uinput mode: manager not needed *\//' main.c
sed -i 's/zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(vkbd_mgr, seat)/NULL/' main.c
sed -i 's/if (keyboard.vkbd == NULL) {/if (0) {/' main.c

# ---- (2) output pinning (Python for reliable multi-line C insertion) ----
python3 - <<'PYEOF'
s = open('main.c').read()

BLOCK = r'''/* --- Armada/Thor: pin the keyboard to an output by connector name (-O) --- */
static char *kbd_target_output = NULL;
static struct wl_output *kbd_selected_output = NULL;
static void kbd_out_name(void *d, struct wl_output *o, const char *nm) {
    if (kbd_target_output && strcmp(nm, kbd_target_output) == 0)
        kbd_selected_output = o;
}
static void kbd_out_geometry(void *d, struct wl_output *o, int32_t x, int32_t y,
    int32_t pw, int32_t ph, int32_t sp, const char *mk, const char *md, int32_t tr) {}
static void kbd_out_mode(void *d, struct wl_output *o, uint32_t f, int32_t w, int32_t h, int32_t r) {}
static void kbd_out_done(void *d, struct wl_output *o) {}
static void kbd_out_scale(void *d, struct wl_output *o, int32_t s) {}
static void kbd_out_desc(void *d, struct wl_output *o, const char *ds) {}
static const struct wl_output_listener kbd_output_listener = {
    .geometry = kbd_out_geometry, .mode = kbd_out_mode, .done = kbd_out_done,
    .scale = kbd_out_scale, .name = kbd_out_name, .description = kbd_out_desc,
};
static void kbd_bind_output(struct wl_registry *reg, uint32_t nm) {
    struct wl_output *o = wl_registry_bind(reg, nm, &wl_output_interface, 4);
    wl_output_add_listener(o, &kbd_output_listener, o);
}
/* --- end output pinning --- */

'''

assert s.count('static void handle_global(void *data') == 1
s = s.replace('static void handle_global(void *data',
              BLOCK + 'static void handle_global(void *data', 1)

assert s.count('    if (strcmp(interface, wl_compositor_interface.name) == 0) {') == 1
s = s.replace('    if (strcmp(interface, wl_compositor_interface.name) == 0) {',
              '    if (strcmp(interface, wl_output_interface.name) == 0) {\n'
              '        kbd_bind_output(registry, name);\n        return;\n    }\n'
              '    if (strcmp(interface, wl_compositor_interface.name) == 0) {', 1)

assert s.count('        } else if (!strcmp(argv[i], "-H")) {') == 1
s = s.replace('        } else if (!strcmp(argv[i], "-H")) {',
              '        } else if ((!strcmp(argv[i], "-O")) || (!strcmp(argv[i], "--output"))) {\n'
              '            if (argv[i + 1]) kbd_target_output = argv[++i];\n'
              '        } else if (!strcmp(argv[i], "-H")) {', 1)

assert s.count('    struct wl_output *current_output_data = NULL;') == 1
s = s.replace('    struct wl_output *current_output_data = NULL;',
              '    wl_display_roundtrip(display);\n'
              '    struct wl_output *current_output_data = kbd_selected_output;', 1)

open('main.c', 'w').write(s)
print("output-pinning patch applied")
PYEOF

echo "=== verification ==="
echo "uinput refs: $(grep -c wvkbd_uinput_key keyboard.c)"
echo "output-pin refs: $(grep -c kbd_selected_output main.c)"
