package app.ipodtouch.emulator;

import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.system.Os;
import android.system.OsConstants;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.style.ForegroundColorSpan;
import android.view.Gravity;
import android.view.WindowManager;
import android.widget.RelativeLayout;
import android.widget.TextView;

import org.libsdl.app.SDLActivity;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.RandomAccessFile;
import java.util.ArrayList;
import java.util.List;

/** Hosts QEMU (libmain.so, entry point SDL_main) inside SDL's surface, with a small heartbeat overlay. */
public class QemuActivity extends SDLActivity {

    private final Handler h = new Handler(Looper.getMainLooper());
    private TextView hud;
    private final long startMs = SystemClock.elapsedRealtime();
    private long lastTicks = -1, lastWall;
    private volatile boolean paused;
    private File stderrLog;

    @Override
    protected String[] getLibraries() {
        return new String[] { "SDL2", "main" };
    }

    @Override
    protected String[] getArguments() {
        File dir = LauncherActivity.ipodDir(this);
        List<String> a = new ArrayList<>();
        a.add("--stderr-file=" + new File(dir, "qemu-stderr.log").getAbsolutePath());
        a.add("-M");
        a.add("iPod-Touch"
                + ",bootrom=" + LauncherActivity.bootrom(this).getAbsolutePath()
                + ",nand=" + LauncherActivity.nand(this).getAbsolutePath()
                + ",nor=" + LauncherActivity.nor(this).getAbsolutePath());
        a.add("-cpu"); a.add("max");
        a.add("-m"); a.add("2G");
        a.add("-serial"); a.add("null");
        a.add("-monitor"); a.add("none");
        if (new File(dir, "debug").exists()) {
            a.add("-D"); a.add(new File(dir, "qemu.log").getAbsolutePath());
            a.add("-d"); a.add("unimp,guest_errors");
        }
        return a.toArray(new String[0]);
    }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        // Don't let Android's screen timeout freeze the emulator or lose the GL surface.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        // Read by SDL when the SDL thread starts: don't block the main loop while paused.
        nativeSetenv("SDL_ANDROID_BLOCK_ON_PAUSE", "0");

        stderrLog = new File(LauncherActivity.ipodDir(this), "qemu-stderr.log");
        hud = new TextView(this);
        hud.setTextSize(9);
        hud.setTextColor(Color.WHITE);
        hud.setBackgroundColor(0x99000000);
        hud.setPadding(8, 4, 8, 4);
        hud.setClickable(false);
        hud.setFocusable(false);
        RelativeLayout.LayoutParams lp = new RelativeLayout.LayoutParams(
                RelativeLayout.LayoutParams.WRAP_CONTENT, RelativeLayout.LayoutParams.WRAP_CONTENT);
        lp.addRule(RelativeLayout.ALIGN_PARENT_TOP);
        lp.addRule(RelativeLayout.ALIGN_PARENT_LEFT);
        mLayout.addView(hud, lp);
        h.post(tick);
    }

    @Override protected void onPause()  { paused = true;  super.onPause(); }
    @Override protected void onResume() { paused = false; super.onResume(); }
    @Override protected void onDestroy() { h.removeCallbacksAndMessages(null); super.onDestroy(); }

    private final Runnable tick = new Runnable() {
        @Override public void run() { update(); h.postDelayed(this, 1000); }
    };

    private long cpuTicks() {
        try (BufferedReader r = new BufferedReader(new FileReader("/proc/self/stat"))) {
            String s = r.readLine();
            String[] f = s.substring(s.lastIndexOf(')') + 2).split(" ");
            return Long.parseLong(f[11]) + Long.parseLong(f[12]);   // utime + stime
        } catch (Exception e) { return -1; }
    }

    private long rssMb() {
        try (BufferedReader r = new BufferedReader(new FileReader("/proc/self/status"))) {
            String l;
            while ((l = r.readLine()) != null)
                if (l.startsWith("VmRSS:")) return Long.parseLong(l.replaceAll("[^0-9]", "")) / 1024;
        } catch (Exception e) { }
        return -1;
    }

    private String lastLogLine() {
        try (RandomAccessFile f = new RandomAccessFile(stderrLog, "r")) {
            long len = f.length();
            if (len == 0) return "";
            byte[] buf = new byte[(int) Math.min(len, 400)];
            f.seek(len - buf.length);
            f.readFully(buf);
            String[] lines = new String(buf).trim().split("\n");
            String l = lines[lines.length - 1];
            return l.length() > 70 ? l.substring(0, 70) : l;
        } catch (Exception e) { return ""; }
    }

    private void update() {
        long now = SystemClock.elapsedRealtime();
        long t = cpuTicks();
        double cpu = -1;
        if (lastTicks >= 0 && t >= 0 && now > lastWall) {
            long hz = Os.sysconf(OsConstants._SC_CLK_TCK);
            cpu = 100.0 * (t - lastTicks) / hz / ((now - lastWall) / 1000.0);
        }
        lastTicks = t; lastWall = now;

        int color; String state;
        if (paused)           { color = Color.RED;               state = "PAUSED"; }
        else if (cpu < 0)     { color = Color.GRAY;              state = "…"; }
        else if (cpu < 3)     { color = Color.rgb(255, 165, 0);  state = "IDLE"; }
        else                  { color = Color.GREEN;             state = "RUN"; }

        long up = (now - startMs) / 1000;
        String line = String.format("● %s  %d:%02d  CPU %s  RSS %d MB", state, up / 60, up % 60,
                cpu < 0 ? "-" : String.format("%.0f%%", cpu), rssMb());
        String log = lastLogLine();
        SpannableStringBuilder sb = new SpannableStringBuilder(line);
        sb.setSpan(new ForegroundColorSpan(color), 0, 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        if (!log.isEmpty()) sb.append("\n").append(log);
        hud.setText(sb);
    }
}
