# Testing on the emulator from Android Studio

What was built in P4–P7 and cannot be proven by the automated tests (243 tests
and 37 goldens pass): real notifications, the system file pickers, the
permission prompt, sound, the lock screen, TalkBack. Each check says what you
should see.

## 1. Set up (once)

1. **Open** `code/flutter_shatibiyyah` in Android Studio (the Flutter and Dart
   plugins installed). When it offers **Pub get**, accept: new packages came in
   (notifications, review, update, background downloads).
2. **Start the emulator** from *Device Manager* → `taysir_pixel` ▶. Started this
   way it has sound (one started from a terminal script does not).
3. Pick `taysir_pixel` in the device list and press **Run ▶** (debug, `main.dart`).
   The first build takes about 6 minutes (new native plugins). Use a full
   **Run**, not hot reload, whenever native code or packages changed.
4. **Recordings** (no audio is bundled; hosting is not up yet): in Android
   Studio's *Terminal* tab, from `code/flutter_shatibiyyah`:

   ```bash
   tool/sideload_audio.sh
   ```

   Then press **Run ▶** again (or *Hot Restart*) so the app looks for them.
   (`tool/sideload_audio.sh atiq` copies only the default reciter, 145 MB.)

> **«أدوات التجربة»** is the last group («نسخة التطوير») of «الإعدادات ← حول تيسير
> الشاطبية» in debug and profile builds, never in the store (release) build.
>
> **Debug or profile?** Use the normal debug **Run** for everything, except the
> checks that start the app *from a notification with the app closed*. A debug
> build opened without Android Studio attached can fail to start on this setup
> ("Could not prepare isolate"). For those, choose *Run → Flutter Run 'main.dart'
> in Profile Mode*. The app's data and the side-loaded recordings stay.

## 2. First run and the reader

To see the first run again: *Device Manager* → ⋮ → **Wipe Data**, or
«الإعدادات ← حول تيسير الشاطبية ← أعد الجولة» (the cards only, ending with «تم»).

- [ ] Splash, then the tour: **3 cards** on page 19, each showing the reader as it
      will look. Card 1 «المخطوط أولًا»: verse 226 washed in gilt, the dock under
      it. Card 2 «الشرح والمراجعة حول البيت»: verse 229 in its ring, with its menu.
      Card 3 «الشروح الثلاثة على جهازك»: the commentary sheet with the three books.
      In «ليلي» the page is the night page. «تخطَّ» is always there; a swipe or
      Back moves between the cards.
- [ ] «اختر القارئ»: with the recording side-loaded, «ابدأ التلاوة» plays.
- [ ] Playback follows verse by verse. The lock screen and the notification
      shade show «البيت N» and the chapter with the reciter; ⏮ ⏯ ⏭ work.
- [ ] A call pauses and does **not** resume: emulator *Extended controls* (⋯) →
      *Phone* → *Call device*, then hang up.
- [ ] Long press a verse: menu with الشرح / تشغيل من هنا / مرجع and the chips.
      Back closes the menu first.

## 2b. The home-screen widgets (plans 6.1, 6.2)

`tool/widget_check.sh` checks both widgets' drawing for every verse on the connected device, and
their day arithmetic, and pairs their states with the design's renders in `build/widgets/`.

«تابع», by hand:

- [ ] Add «تابع» from the launcher's widgets **before opening the app**: it shows verse 1 and
      «تنزيل». «تنزيل» opens «التنزيلات».
- [ ] With a recording on the device: ▶ plays without opening the app, ❚❚ pauses. The widget
      follows the verse, a few seconds behind at most.
- [ ] Swipe the app away, then ▶: «جارٍ تشغيل التلاوة…» shows for a moment and the recitation
      starts. The app does not open.
- [ ] A tap on the verse opens «المتن» on it.
- [ ] «المظهر ← تلقائي», then the system's dark theme on and off: the widget follows, with
      the app closed. «ورقي» and «ليلي» hold whatever the system is in.

«بيت اليوم», by hand:

- [ ] Add it: verse 1 that day, with its number and its chapter. A tap opens «المتن» on it.
- [ ] Make it 2×2: each hemistich wraps inside itself, nothing is cut.
- [ ] The next morning it shows verse 2 (or set the device's date a day on: it changes at once).
- [ ] A verse with reader symbols is in the rubric ink with dotted underlines; at night, in the
      ink chosen in «لون الحبر الليلي». «إبراز رموز القراء وأسمائهم» off: plain ink.

## 3. Study and navigation (P6)

- [ ] «مرجع» on a verse: colour and tag, then a ribbon on the page.
      «ملاحظة»: saved, and listed in «الرئيسية ← الملاحظات».
- [ ] «الرئيسية»: «تابع من حيث توقفت», the three tabs, and «السجل» after a minute
      of listening.
- [ ] «الفهرس»: listening bars, gold current chapter, a tick when finished.
- [ ] Search: type `٢٢٩` for a card that opens verse 229 (no text results). Type
      a word from one of your notes for «ملاحظاتك». «ورش» gives «عرض المزيد» under
      the books. Reopen search to see «بحثت مؤخرًا».
- [ ] «رموز القراء»: the three tabs; tapping a code opens its verse.

## 4. Settings and backup (P7)

- [ ] «الإعدادات ← السمة ورقية»: the whole app turns paper.
      «حجم النص ٢٠٠٪»: text mode is larger.
- [ ] «نسخ احتياطي ← إنشاء نسخة الآن»: the system *save* screen opens with
      `shatibiyyah-backup-YYYY-MM-DD.json`. Save it to *Downloads*; the card then
      shows the time and size.
- [ ] Delete a note, then «استعادة من ملف» → pick that file: «تمت الاستعادة…», and
      the note is back. Restore again: «لا جديد في هذه النسخة».
- [ ] Restore any other file (e.g. an image): «الملف ليس نسخة احتياطية…».

## 4b. «حول»: the privacy line and «رأيك ودعمك» (plan 5.4, ADR 0033)

- [ ] «الإعدادات ← حول تيسير الشاطبية»: «في التطبيق» ends with «مراجعك وملاحظاتك / تبقى على
      جهازك». The row does nothing when tapped.
- [ ] «أرسل ملاحظة»: the mail app opens on a letter to `kSupportEmail`
      (`lib/app/app_links.dart`), subject «ملاحظة على تيسير الشاطبية», and under an
      empty body one line with the version, the content and this device. On an emulator with
      no mail account the address is copied instead and a message says so.
- [ ] «شارك التطبيق»: the system's share sheet, with three lines (the name, the app's line, the
      Google Play link).
- [ ] «قيّم التطبيق»: Google Play opens on the app's page. Until the app is published the page
      says it was not found.
- [ ] The backup is off: `adb shell dumpsys package com.shatibiyyah.app | grep -o ALLOW_BACKUP`
      prints nothing.

## 5. Reminders

- [ ] «☰ ← التنبيهات ← فائدة اليوم»: Android asks for notification permission.
      **Allow**: the switch turns on and «الوقت ٧:٠٠» appears. The preview shows
      today's verse and «الخلاصة: …».
- [ ] Deny once (*Settings → Apps → تيسير الشاطبية → Notifications*: off, then try
      again): the switch stays off with «لم يُسمح بالإشعارات…».
- [ ] «حول ← أدوات التجربة ← أرسل فائدة اليوم الآن»: a notification appears with
      the star icon. Expand it for the full text. **Tap it**: the app opens
      Al-Wafi at that verse.
- [ ] «أدوات التجربة ← تذكير الباب ← أرسل» → tap the notification: the reader
      opens on your current verse.
- [ ] *(Profile mode)* «جدولة فائدة اليوم بعد دقيقتين», then **swipe the app
      away**: the notification comes within about 2–10 minutes (inexact on
      purpose). Tap it with the app closed: the app starts and opens Al-Wafi
      there.
- [ ] Scheduled alarms can be listed while waiting:

      ```bash
      adb shell dumpsys alarm | grep -A2 com.shatibiyyah.app
      ```

- [ ] Optional: with «فائدة اليوم» on, the alarms survive a reboot
      (*Device Manager* → ⋮ → *Cold Boot Now*, then the `dumpsys` line again).

## 6. Rating, update banner, downloads

- [ ] **Update banner:** «أدوات التجربة ← شريط التحديث ← أظهر», then «الإعدادات»
      shows «إصدار جديد من التطبيق متاح». «إخفاء» hides it. «تحديث» does nothing
      outside a Play install; that's expected.
- [ ] **Rating:** the Play review sheet only appears for an app installed from
      Google Play (internal testing track or internal app sharing). In a debug
      build «طلب التقييم ← اطلب» must just not crash. The real test is on the
      closed-test build: finish a chapter (listen to all its verses).
- [ ] **Background downloads:** waiting for hosting (Q1a). Until the files are
      online the downloads screen can only be checked with the side-loaded
      recordings (on device, delete with confirmation, storage line).

## 7. Accessibility

- [ ] *Settings → Accessibility → Display size and text → Font size* at the
      maximum: every screen still fits (checked at 200 % in the tests).
- [ ] *Settings → Accessibility → Remove animations*: the shamsa stops turning,
      and text mode jumps instead of scrolling.
- [ ] **TalkBack**: on the page each verse is read as one item («البيت ٢٢٦: …»);
      double-tap selects it, double-tap-and-hold opens its menu. In text mode
      each row is one item.
      The `taysir_pixel` image (*Google APIs*) may not include TalkBack. If
      *Accessibility* has no TalkBack entry, check on a real phone, or create a
      second AVD with a **Google Play** system image, which includes the
      Accessibility Suite.

## 8. Tablet (P8)

Create a tablet emulator once: *Device Manager* → **+** → *Create Virtual
Device* → **Pixel Tablet** → the same Android 16 image as `taysir_pixel`.
Run the app on it (choose it in the device selector) and side-load the audio
with `ANDROID_SERIAL=emulator-5556 tool/sideload_audio.sh` (the serial is shown
by `adb devices`).

- [ ] The tablet turns (the phone does not): rotate with the emulator's rotate
      buttons; the page re-lays itself out and keeps the highlighted verse.
- [ ] Long press a verse → «الشرح»: the commentary opens **beside** the page
      (page on the right), not as a new screen. Back closes the panel.
- [ ] Drag the divider: the page's share moves between 30 % and 70 %. Rotate and
      back: each orientation keeps its own position.
- [ ] Play: with «يتبع التلاوة» on, each new verse moves the panel. Scroll in the
      panel while it plays: it stays put until you stop scrolling for about
      6 seconds. Switch «يتبع التلاوة» off: it stays on its verse.
- [ ] «التالي» inside the panel moves it on and turns following off.
- [ ] «حجم الخط» cycles three sizes; «قارن الشروح» shows the three books in
      columns in landscape (with «مزامنة التمرير»), as pages in portrait.
- [ ] Home, settings and search keep a reading width instead of spanning the
      whole tablet.

## If something fails

Note the screen and the step, and copy the **Run** tab output (errors show
there). A screenshot helps for anything visual.
