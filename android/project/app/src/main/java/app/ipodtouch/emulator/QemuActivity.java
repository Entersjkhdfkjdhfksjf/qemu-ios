package app.ipodtouch.emulator;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

import org.libsdl.app.SDLActivity;

/** Hosts QEMU (libmain.so, entry point SDL_main) inside SDL's surface. */
public class QemuActivity extends SDLActivity {

    @Override
    protected String[] getLibraries() {
        return new String[] { "SDL2", "main" };
    }

    @Override
    protected String[] getArguments() {
        File dir = LauncherActivity.ipodDir(this);
        List<String> a = new ArrayList<>();
        a.add("-M");
        a.add("iPod-Touch"
                + ",bootrom=" + LauncherActivity.bootrom(this).getAbsolutePath()
                + ",nand=" + LauncherActivity.nand(this).getAbsolutePath()
                + ",nor=" + LauncherActivity.nor(this).getAbsolutePath());
        a.add("-cpu"); a.add("max");
        a.add("-m"); a.add("2G");
        a.add("-serial"); a.add("null");
        a.add("-monitor"); a.add("none");
        // Create an empty file named "debug" in the ipod folder to get a QEMU log.
        if (new File(dir, "debug").exists()) {
            a.add("-D"); a.add(new File(dir, "qemu.log").getAbsolutePath());
            a.add("-d"); a.add("unimp,guest_errors");
        }
        return a.toArray(new String[0]);
    }
}
