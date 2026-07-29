#!/bin/bash
# Patch wvkbd to inject keystrokes via /dev/uinput instead of the wlroots
# virtual-keyboard protocol (KWin doesn't expose it). All wvkbd key output
# already uses evdev keycodes, so we just redirect the three protocol calls.
set -euo pipefail
cd wvkbd

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

# main.c: don't require the (absent) virtual-keyboard manager
sed -i 's/if (vkbd_mgr == NULL) {/if (0) { \/* uinput mode: manager not needed *\//' main.c
sed -i 's/zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(vkbd_mgr, seat)/NULL/' main.c
sed -i 's/if (keyboard.vkbd == NULL) {/if (0) {/' main.c

echo "=== patch verification ==="
echo "shim inserted: $(grep -c wvkbd_uinput_key keyboard.c) refs"
echo "manager guarded: $(grep -c 'if (0)' main.c) sites"
