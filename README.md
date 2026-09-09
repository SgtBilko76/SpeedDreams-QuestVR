<img width="800" height="450" alt="speed-dreams-20-splash" src="https://github.com/user-attachments/assets/a8886516-eb6b-4012-8361-5c5cb174e9e9" />


<img width="1024" height="768" alt="collage" src="https://github.com/user-attachments/assets/c3bc830d-822a-415c-9c5e-75ac61d7a95c" />

https://www.speed-dreams.org/

Speed Dreams VR 0.9.2-beta
========================

Speed Dreams 2.4 as a standalone Meta Quest application: stereo rendering
through OpenXR, a curved menu panel, and the full game in one APK.

Quest 2, Quest 3, Quest Pro. About 500 MB free on the headset.


Installing
----------

Sideload it, however you normally do - SideQuest, or:

    adb install -r SpeedDreamsVR-0.9.2-beta.apk

The game appears in the headset's library under Unknown Sources.

The first launch takes an extra half minute or so: the game data is unpacked
out of the APK to /sdcard/SpeedDreamsVR, where it stays. Later versions reuse
that directory, so an update is just the new APK.


More cars and tracks
--------------------

This carries what Speed Dreams itself ships: one track and one car, which is
enough to race. Another 74 tracks and 90 cars are published separately - get
them from inside the headset, in Options -> Downloads, over wifi. Pick the ones
you want; the whole set is about 5.4 GB.


Controls
--------

    Right trigger        throttle          Left trigger      brake
    Left stick           steer             Left stick click  reverse gear
    Right grip           shift up          Left grip         shift down
    A                    ABS / confirm     X                 ASR
    Right stick click    rear-view mirror
    Y                    next camera; hold 1 second to recentre the menu panel

If the menu panel is not in front of you, hold Y for a second - it is anchored
to the room, not to your head, so it stays where it was when you last moved.


Settings
--------

/sdcard/SpeedDreamsVR/vr.cfg holds the things worth trying without a new build:
eye buffer scale, refresh rate, antialiasing, where the mirror sits, and the
steering curve. It is commented; edit it and restart the app. Updates leave it
alone once it is there.

Everything else is in the game's own Options menu. If a track will not hold
frame rate, turn the sky dome off first - with it on, nothing is distance
culled and the whole track is drawn every frame, twice.


Known limits
------------

- Practice and qualifying run one car at a time. That is how the game works,
  not a fault of the port: use Quick Race or a championship to race opponents.
