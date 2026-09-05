package com.speeddreamsvr;

import static android.system.Os.setenv;

import java.io.File;
import java.util.Locale;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.Settings;
import android.util.Log;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

/**
 * Host activity for Speed Dreams VR. Modelled on QuakeQuest's GLES3JNIActivity:
 * a plain SurfaceView, and the native app thread does everything (OpenXR, GL, game).
 * The game data lives in /sdcard/SpeedDreamsVR (pushed with adb), so the app needs
 * all-files access.
 */
@SuppressLint("SdCardPath")
public class SDVRActivity extends Activity implements SurfaceHolder.Callback
{
    private static final String TAG = "SpeedDreamsVR";
    private static final int REQUEST_STORAGE = 2294;
    private static final int REQUEST_MANAGE_ALL_FILES = 2296;

    static
    {
        String manufacturer = Build.MANUFACTURER.toLowerCase(Locale.ROOT);
        if (manufacturer.contains("oculus")) {
            manufacturer = "meta";
        }
        try {
            System.loadLibrary("openxr_loader");
        } catch (Throwable e) {
            Log.e(TAG, "openxr_loader not loadable: " + e);
        }
        try {
            setenv("OPENXR_HMD", manufacturer, true);
        } catch (Exception e) {
            // ignore
        }
        System.loadLibrary("sdvr");
    }

    private SurfaceHolder mSurfaceHolder;
    private long mNativeHandle;
    private String mDataDir = "/sdcard/SpeedDreamsVR";

    @Override
    protected void onCreate(Bundle icicle)
    {
        Log.v(TAG, "SDVRActivity::onCreate()");
        super.onCreate(icicle);

        SurfaceView view = new SurfaceView(this);
        setContentView(view);
        view.getHolder().addCallback(this);

        File ext = Environment.getExternalStorageDirectory();
        if (ext != null) {
            mDataDir = new File(ext, "SpeedDreamsVR").getAbsolutePath();
        }

        checkPermissionsAndInitialize();
    }

    private void checkPermissionsAndInitialize()
    {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (!Environment.isExternalStorageManager()) {
                Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                intent.setData(Uri.fromParts("package", getPackageName(), null));
                startActivityForResult(intent, REQUEST_MANAGE_ALL_FILES);
                return;
            }
        } else if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[] { Manifest.permission.WRITE_EXTERNAL_STORAGE,
                                              Manifest.permission.READ_EXTERNAL_STORAGE }, REQUEST_STORAGE);
            return;
        }
        create();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data)
    {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_MANAGE_ALL_FILES) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) {
                create();
            } else {
                Log.e(TAG, "All-files access not granted; exiting");
                finishAffinity();
                System.exit(0);
            }
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults)
    {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_STORAGE && grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            create();
        } else {
            System.exit(0);
        }
    }

    private void create()
    {
        if (mNativeHandle != 0) {
            return;
        }
        new File(mDataDir).mkdirs();
        Log.v(TAG, "data dir = " + mDataDir);
        mNativeHandle = SDVRLib.onCreate(this, mDataDir);
        // If the surface already exists (permission round-trip), hand it over now.
        if (mSurfaceHolder != null) {
            SDVRLib.onSurfaceCreated(mNativeHandle, mSurfaceHolder.getSurface());
        }
    }

    /** Called from native code when the game wants to quit. */
    public void shutdown()
    {
        Log.v(TAG, "shutdown() requested by native code");
        finishAffinity();
        System.exit(0);
    }

    @Override
    protected void onStart()
    {
        Log.v(TAG, "SDVRActivity::onStart()");
        super.onStart();
        if (mNativeHandle != 0) {
            SDVRLib.onStart(mNativeHandle, this);
        }
    }

    @Override
    protected void onResume()
    {
        Log.v(TAG, "SDVRActivity::onResume()");
        super.onResume();
        if (mNativeHandle != 0) {
            SDVRLib.onResume(mNativeHandle);
        }
    }

    @Override
    protected void onPause()
    {
        Log.v(TAG, "SDVRActivity::onPause()");
        if (mNativeHandle != 0) {
            SDVRLib.onPause(mNativeHandle);
        }
        super.onPause();
    }

    @Override
    protected void onStop()
    {
        Log.v(TAG, "SDVRActivity::onStop()");
        if (mNativeHandle != 0) {
            SDVRLib.onStop(mNativeHandle);
        }
        super.onStop();
    }

    @Override
    protected void onDestroy()
    {
        Log.v(TAG, "SDVRActivity::onDestroy()");
        if (mSurfaceHolder != null && mNativeHandle != 0) {
            SDVRLib.onSurfaceDestroyed(mNativeHandle);
        }
        if (mNativeHandle != 0) {
            SDVRLib.onDestroy(mNativeHandle);
        }
        super.onDestroy();
        mNativeHandle = 0;
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder)
    {
        Log.v(TAG, "SDVRActivity::surfaceCreated()");
        mSurfaceHolder = holder;
        if (mNativeHandle != 0) {
            SDVRLib.onSurfaceCreated(mNativeHandle, holder.getSurface());
        }
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height)
    {
        Log.v(TAG, "SDVRActivity::surfaceChanged()");
        mSurfaceHolder = holder;
        if (mNativeHandle != 0) {
            SDVRLib.onSurfaceChanged(mNativeHandle, holder.getSurface());
        }
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder)
    {
        Log.v(TAG, "SDVRActivity::surfaceDestroyed()");
        if (mNativeHandle != 0) {
            SDVRLib.onSurfaceDestroyed(mNativeHandle);
        }
        mSurfaceHolder = null;
    }
}
