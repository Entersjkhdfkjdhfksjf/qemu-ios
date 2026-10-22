package app.ipodtouch.emulator;

import android.app.Activity;
import android.content.ClipData;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.OpenableColumns;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * First screen: import the three firmware files (bootrom_240_4, nor_n72ap.bin,
 * nand_n72ap.zip) into app-private storage, then start the emulator.
 * No Apple firmware is bundled in the APK.
 */
public class LauncherActivity extends Activity {
    private static final int REQ_IMPORT = 1;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private TextView status;
    private Button start, imp, clear, logBtn, dbgBtn;
    private volatile boolean busy;

    static File ipodDir(Context c) { return new File(c.getFilesDir(), "ipod"); }
    static File bootrom(Context c) { return new File(ipodDir(c), "bootrom_240_4"); }
    static File nor(Context c)     { return new File(ipodDir(c), "nor_n72ap.bin"); }
    static File nand(Context c)    { return new File(ipodDir(c), "nand"); }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        int pad = (int) (24 * getResources().getDisplayMetrics().density);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad * 2, pad, pad);
        root.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView title = new TextView(this);
        title.setText("iPod touch 2G (QEMU)");
        title.setTextSize(24);
        root.addView(title);

        status = new TextView(this);
        status.setTextSize(15);
        status.setPadding(0, pad, 0, pad);
        status.setTextIsSelectable(true);
        ScrollView sv = new ScrollView(this);
        sv.addView(status);
        root.addView(sv, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));

        imp = new Button(this);
        imp.setText("Import firmware files…");
        imp.setOnClickListener(v -> pick());
        root.addView(imp);

        start = new Button(this);
        start.setText("Start iPod touch");
        start.setOnClickListener(v -> startActivity(new Intent(this, QemuActivity.class)));
        root.addView(start);

        logBtn = new Button(this);
        logBtn.setText("Show QEMU log");
        logBtn.setOnClickListener(v -> showLog());
        root.addView(logBtn);

        dbgBtn = new Button(this);
        dbgBtn.setOnClickListener(v -> {
            File f = new File(ipodDir(this), "debug");
            if (f.exists()) f.delete(); else { ipodDir(this).mkdirs(); try { f.createNewFile(); } catch (IOException e) { } }
            refresh();
        });
        root.addView(dbgBtn);

        clear = new Button(this);
        clear.setText("Delete imported files");
        clear.setOnClickListener(v -> {
            new Thread(() -> { deleteRecursive(ipodDir(this)); ui.post(this::refresh); }).start();
        });
        root.addView(clear);

        setContentView(root);
        refresh();
    }

    @Override
    protected void onResume() { super.onResume(); refresh(); }

    private static String mark(boolean ok) { return ok ? "✓ " : "✗ "; }

    private boolean nandOk() {
        String[] l = nand(this).list();
        return nand(this).isDirectory() && l != null && l.length > 0;
    }

    private void refresh() {
        boolean br = bootrom(this).isFile(), no = nor(this).isFile(), na = nandOk();
        if (!busy) {
            status.setText(mark(br) + "bootrom_240_4\n" + mark(no) + "nor_n72ap.bin\n"
                    + mark(na) + "nand_n72ap.zip (extracted to nand/)\n\n"
                    + (br && no && na ? "Ready."
                       : "Download the three files from the qemu-ios iPod touch 2G release, then tap Import and select all of them."));
        }
        dbgBtn.setText(new File(ipodDir(this), "debug").exists()
                ? "Verbose QEMU log: ON (tap to turn off)" : "Verbose QEMU log: off (tap to turn on)");
        start.setEnabled(!busy && br && no && na);
        imp.setEnabled(!busy);
        clear.setEnabled(!busy);
    }

    private static String tail(File f, int max) {
        try (RandomAccessFile r = new RandomAccessFile(f, "r")) {
            long len = r.length();
            byte[] b = new byte[(int) Math.min(len, max)];
            r.seek(len - b.length);
            r.readFully(b);
            return new String(b);
        } catch (Exception e) { return "(none)"; }
    }

    private void showLog() {
        File d = ipodDir(this);
        status.setText("== qemu-stderr.log (last 4000 chars) ==\n" + tail(new File(d, "qemu-stderr.log"), 4000)
                + "\n\n== qemu.log (verbose, last 3000 chars) ==\n" + tail(new File(d, "qemu.log"), 3000));
    }

    private void setStatus(String s) { ui.post(() -> status.setText(s)); }

    private void pick() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("*/*");
        i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        startActivityForResult(i, REQ_IMPORT);
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req != REQ_IMPORT || res != RESULT_OK || data == null) return;
        List<Uri> uris = new ArrayList<>();
        ClipData cd = data.getClipData();
        if (cd != null) for (int i = 0; i < cd.getItemCount(); i++) uris.add(cd.getItemAt(i).getUri());
        else if (data.getData() != null) uris.add(data.getData());
        busy = true; refresh();
        new Thread(() -> {
            String err = null;
            try {
                for (Uri u : uris) importOne(u);
            } catch (Exception e) {
                err = e.toString();
            }
            busy = false;
            final String fe = err;
            ui.post(() -> { refresh(); if (fe != null) status.setText("Import failed: " + fe); });
        }).start();
    }

    private String displayName(Uri u) {
        try (Cursor c = getContentResolver().query(u, null, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                int ix = c.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (ix >= 0) return c.getString(ix);
            }
        }
        return u.getLastPathSegment();
    }

    private void importOne(Uri u) throws IOException {
        String name = displayName(u);
        File dir = ipodDir(this);
        dir.mkdirs();
        try (InputStream in = getContentResolver().openInputStream(u)) {
            if (in == null) throw new IOException("cannot open " + name);
            if (name.toLowerCase().endsWith(".zip")) {
                unzip(in, dir, name.toLowerCase().contains("nand"), name);
            } else {
                setStatus("Copying " + name + "…");
                copy(in, new File(dir, name.replaceAll("[/\\\\]", "_")));
            }
        }
    }

    private void unzip(InputStream in, File dir, boolean nandHint, String label) throws IOException {
        String base = dir.getCanonicalPath() + File.separator;
        ZipInputStream z = new ZipInputStream(in);
        ZipEntry e;
        boolean first = true, prefix = false;
        int n = 0;
        while ((e = z.getNextEntry()) != null) {
            String en = e.getName();
            if (first) { prefix = nandHint && !en.startsWith("nand/"); first = false; }
            if (prefix) en = "nand/" + en;
            File out = new File(dir, en);
            if (!out.getCanonicalPath().startsWith(base)) throw new IOException("bad zip entry " + en);
            if (e.isDirectory()) { out.mkdirs(); continue; }
            out.getParentFile().mkdirs();
            copy(z, out, false);
            if (++n % 25 == 0) setStatus("Extracting " + label + "… " + n + " files");
        }
    }

    private static void copy(InputStream in, File out) throws IOException { copy(in, out, true); }

    private static void copy(InputStream in, File out, boolean closeIn) throws IOException {
        try (OutputStream o = new FileOutputStream(out)) {
            byte[] buf = new byte[1 << 16];
            int r;
            while ((r = in.read(buf)) > 0) o.write(buf, 0, r);
        }
    }

    private static void deleteRecursive(File f) {
        File[] kids = f.listFiles();
        if (kids != null) for (File k : kids) deleteRecursive(k);
        f.delete();
    }
}
