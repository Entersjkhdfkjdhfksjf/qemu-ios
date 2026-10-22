/*
 * QEMU System Emulator
 *
 * Copyright (c) 2003-2020 Fabrice Bellard
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "qemu/osdep.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "qemu-main.h"
#include "sysemu/sysemu.h"

#ifdef CONFIG_SDL
#include <SDL.h>
#endif

int qemu_default_main(void)
{
    int status;

    status = qemu_main_loop();
    qemu_cleanup(status);

    return status;
}

int (*qemu_main)(void) = qemu_default_main;

int main(int argc, char **argv)
{
#if defined(__ANDROID__) && defined(CONFIG_SDL)
    /*
     * Android discards stdout/stderr of apps. "--stderr-file=PATH" (injected by
     * the Java side) sends both to a file so the app can show QEMU's messages.
     */
    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "--stderr-file=", 14) == 0) {
            if (freopen(argv[i] + 14, "w", stderr)) {
                setvbuf(stderr, NULL, _IOLBF, 0);
                dup2(fileno(stderr), 1);
            }
            memmove(&argv[i], &argv[i + 1], (argc - i) * sizeof(char *));
            argc--;
            break;
        }
    }
#endif
    qemu_init(argc, argv);
    return qemu_main();
}

#if defined(__ANDROID__) && defined(CONFIG_SDL)
/*
 * SDL.h renames the function above to SDL_main (called from SDLActivity).
 * Keep a real main() so the intermediate executable still links before the
 * Android build relinks the same objects as libmain.so.
 */
#undef main
int main(int argc, char **argv)
{
    return SDL_main(argc, argv);
}
#endif
