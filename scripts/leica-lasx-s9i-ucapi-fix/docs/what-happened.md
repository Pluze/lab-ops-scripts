# What Happened

This repair was built for a failure mode where the microscope hardware was still
working, but LAS X could not display a valid image.

## Observed Behavior

- Windows detected the Leica S9i camera.
- Windows Camera could show the microscope image.
- LAS X detected the S9i camera.
- LAS X Live view was black.
- In some sessions, LAS X showed only a series of incorrect 4:3 resolution
  options.
- In later sessions, normal 16:9 modes returned, but the Live view still showed
  black frames.
- White balance or camera-control commands could hang.

## Cause Layer 1: Dynamic Hardware Tree Pollution

LAS X stores a dynamic hardware tree in:

```text
C:\ProgramData\Leica Microsystems\LAS X\Calibration Data\DefaultDynamicWidefieldTree.xlhw
```

In the diagnosed case, this file contained many duplicate UCAPI camera nodes for
the same S9i camera and demo camera. This confused LAS X camera capability
enumeration and produced an incorrect resolution list.

The script removes duplicate `CDrvOOCAMIUCAPI` nodes while preserving the first
instance of each camera name.

## Cause Layer 2: UCAPI / DirectShow Format Mismatch

The S9i was exposed to LAS X through Windows UVC/DirectShow:

```text
LAS X -> UCAPI -> ucDShow.dll -> Windows USB Video Device
```

Windows Camera could show the image because it uses the modern Windows camera
stack. LAS X 3.x uses Leica's older UCAPI DirectShow wrapper.

LAS X could enumerate the camera and create a 1920x1080 preview object, but the
pixels received by LAS X were black. This suggested that the stream object was
valid enough to start, but the old DirectShow wrapper was not accepting or
interpreting the returned format correctly.

Leica's older LAS configuration included this compatibility switch:

```text
UCDSHOW_ACCEPT_UNEXPECTED_FORMAT="1"
```

Adding the same switch to the UCAPI installed config made `ucDShow.dll` more
tolerant of the returned DirectShow format and restored the image in the
diagnosed system.

## Why Windows Camera Can Work While LAS X Fails

Windows Camera and LAS X do not use the camera in exactly the same way.

Windows Camera can use the current Windows UVC camera path directly. LAS X 3.x
uses Leica's older UCAPI and DirectShow wrapper. A camera can therefore work in
Windows Camera while failing inside LAS X.

## Practical Rule

- If the LAS X resolution list is wrong, suspect hardware-tree duplicate or stale
  camera nodes.
- If the resolution list is correct but Live view is black, suspect the
  UCAPI/DirectShow compatibility path.
- If Windows Camera works but LAS X does not, the hardware is probably not the
  primary failure point.

