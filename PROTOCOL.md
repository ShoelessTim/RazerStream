# Razer Stream Controller wire protocol

Everything here was reverse engineered against real hardware (firmware 0.2.8).
It matches the Loupedeck Live family; the Razer Stream Controller is that
device rebranded. Each of these cost real debugging time; they are written down
so nobody has to bleed for them again.

## Identity and transport

- USB vendor 0x1532, product 0x0D06 (the Stream Controller X is 0x0D09).
- The device presents as a USB CDC serial port, e.g. `/dev/cu.usbmodemXXXX`.
- Serial config: 9600 baud, 8 data bits, no parity, 1 stop bit (8N1), no flow
  control. Raw mode. Notably one stop bit, not two as some notes claim.
- Use a blocking read on a background thread. A DispatchIO stream treats an
  idle-tty read of 0 as EOF and stops delivering forever; a plain blocking
  `read()` loop avoids that.

## Handshake

The host opens the port and sends a WebSocket upgrade request as plain text:

```
GET /index.html
HTTP/1.1
Connection: Upgrade
Upgrade: websocket
Sec-WebSocket-Key: 123abc

```

The trailing blank line is mandatory; without the final `\n\n` the device never
answers. The device replies with `HTTP/1.1 101 Switching Protocols` and the
usual headers, terminated by `\r\n\r\n`. Wait for that full terminator before
switching the parser to WebSocket frames. After the upgrade, all traffic is
WebSocket binary frames.

## Framing

Both directions use RFC 6455 binary frames (opcode 0x2), first byte 0x82.

- Host to device frames set the MASK bit with an all-zero mask key. Layout for
  a small payload: `82  80|len  00 00 00 00  <payload>`. Masking with zero is a
  no-op, so the payload is sent in the clear; the device still requires the bit.
  Large payloads use `82 FF <8-byte big-endian length> 00 00 00 00 <payload>`.
- Device to host frames are unmasked: `82  len  <payload>` for small payloads.

## Message payload

Inside each frame the protocol message is:

```
byte 0   message length (header + data, capped at 0xFF)
byte 1   command
byte 2   transaction id (cycles 1..255, never 0)
byte 3+  command data
```

### Commands (host to device)

- 0x02 SET_COLOR; data `[buttonID, r, g, b]`. Sets a physical button LED.
- 0x03 SET_SERIAL / serial request.
- 0x07 VERSION request.
- 0x09 SET_BRIGHTNESS; data is a single byte 0..10. A leading 0x00 is read as
  brightness zero and blanks the panel; send exactly one byte.
- 0x0F DRAW; data is the 2-byte display id. Refreshes the screen after a
  framebuffer write.
- 0x10 FRAMEBUFF; see display writes below.
- 0x1B SET_VIBRATION; data `[haptic]`.

### Display writes

One logical display spans the whole screen; id is the two bytes `00 4D` ("\0M").
The unified space is 480x270: left knob strip x 0..60, center tile grid
x 60..420, right knob strip x 420..480.

FRAMEBUFF payload:

```
display id   2 bytes   00 4D
x            2 bytes   big-endian
y            2 bytes   big-endian
width        2 bytes   big-endian
height       2 bytes   big-endian
pixels       width*height*2 bytes, RGB565 little-endian
```

Follow every FRAMEBUFF with a DRAW carrying the same display id, or the pixels
stay in the buffer and never appear. Rows are top first; do not flip vertically
or the image comes out upside down. Pace consecutive framebuffer writes about
60 ms apart; blasting all twelve tiles back to back overruns the buffer and
nothing renders.

Tiles are 90x90. Tile n sits at x = 60 + (n % 4) * 90, y = (n / 4) * 90.
Knob strips are 60x90; left strip x 0, right strip x 420, stacked by row.

## Events (device to host)

Same message shape; byte 1 is the event type.

- 0x00 button; data `[id, state]`, state 0 is press, nonzero is release.
- 0x01 knob; data `[id, delta]`, delta is a signed int8.
- 0x4D / 0x52 touch; data `[?, xHi, xLo, yHi, yLo, touchId]`.
- 0x6D / 0x72 touch end; same shape.
- 0x07 version reply; three bytes major, minor, patch.
- 0x03 serial reply; ASCII serial number.

### Control id map (verified on hardware)

The device enumerates knob presses first, then physical buttons:

- ids 1..3 are the left knobs, top to bottom
- ids 4..6 are the right knobs, top to bottom
- ids 7..14 are the eight physical buttons, left to right

For LEDs, physical button n uses SET_COLOR button id 7 + n. Button 1 (id 7) is
the device status light; the device drives it, so never write it.

## Session behavior

- The device hands the screen to the host on connect; if the host draws nothing,
  the screen is blank. Hold the session open to keep content on screen.
- On disconnect the read side sees an error or a flood of EOFs; treat that as a
  disconnect, close, and reconnect. The device answers the upgrade handshake
  fresh on each new session.
- Killing a process mid-framebuffer-write can wedge the device parser; a USB
  replug clears it.
