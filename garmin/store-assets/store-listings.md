# Connect IQ Store listings

Copy/paste text for the two Connect IQ Store submissions, plus the form answers.
Store images are in this folder: hero-1440x720.png, cover-500x500.png, device-icon-128.png.

---

## L308 Light  (manual watch-app)

**Title**
```
L308 Light
```

**Description**
```
A Garmin app for controlling a Magene L308 taillight over Bluetooth. Connect to
the light and switch between the patterns saved on it, without pulling out your
phone or the vendor app.

You don't need this app to use the light. Magene's OnelapFit app manages it too.
This is just an optional way to control it from your Garmin.

- Scans for your L308 and connects over Bluetooth
- Shows the current pattern and steps to the next or previous one
- Remembers the last pattern you set
- Glance tile so you can check it without opening the app

Requires a Magene L308 taillight. It only sends the standard pattern-select
commands the light already uses, and never writes to firmware.

Unofficial. Not affiliated with or endorsed by Magene. For use with hardware you own.
```

**What's New (1.0.0)**
```
First release. Connect to a Magene L308 over Bluetooth and change its pattern from your Garmin.
```

**Form answers**
- Category: Tools/Utilities (or Safety). Subcategory: closest cycling/utility.
- Hero image: hero-1440x720.png
- Cover image (500x500): cover-500x500.png
- Device icons (128x128, optional): device-icon-128.png
- Privacy policy / collects user data: No
- ANT+ profiles: No (Bluetooth only)
- Regional limits: No
- Screen images: capture in the simulator (connected "Pattern 3 / 10" screen + glance tile)
- Email: a non-personal address
- Source code URL: https://github.com/mchardysam/magene-l308-taillight (once Garmin source is pushed)
- Review notification: Yes
- App migration: Yes
- Monetization: No
- Companion app: (blank)
- Additional hardware Product URL: https://s.click.aliexpress.com/e/_c3JsQmHj

---

## L308 Auto  (data field)

**Title**
```
L308 Auto
```

**Description**
```
An optional Garmin data field that changes a Magene L308 taillight's pattern
automatically while you ride, to match how you're riding and to help the light's
battery last.

You don't need this to use the light. Magene's own OnelapFit app manages it, and
this is just for people who like to control the light from their Garmin.

You pick a pattern for each situation in the settings, and the field switches the
light as things change during the ride:

- Group mode holds a steady, calmer pattern so you're not flashing the rider on your wheel
- A speed threshold can switch to a different pattern
- When the light's battery gets low it can drop to a lighter pattern to make it last
- The rest of the time it holds your default

It connects once when the ride starts and only writes to the light when the pattern
needs to change. There is also a manual mode that leaves the light alone.

Add it to a data screen on one of your ride profiles. Requires a Magene L308
taillight. Unofficial, not affiliated with or endorsed by Magene. For use with
hardware you own.
```

**What's New (1.0.0)**
```
First release. Automatic pattern switching for a Magene L308 from ride data, with manual and group modes.
```

**Form answers**
- Category: Data Fields. Subcategory: closest cycling/utility.
- ANT+ profiles: No (radar rule removed for store approval; the field uses Bluetooth only)
- Everything else: same as L308 Light above (No user data, No regional limits, No monetization, etc.)
```
