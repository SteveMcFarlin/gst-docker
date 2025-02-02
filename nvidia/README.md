# This is an archived directory. It was origionaly used to investigate GPU usage for rendtion.

### Notes

This build should be done by hand, and should only have to be done periodically... like once a year.

Use Dockerfile.gpu to build the image.

https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html#installation-guide

Note that simply installing the nvidia driver and cuda toolkit via apt does not work with gstreamer when installing it from apt. Hence why this build exists. On a positive note this does build gstreamer which is nice. To speed up this build we could potentially install the drivers via apt, and then compile gstreamer from source. Using the cuda docker image does not speed anything up when it was tested.

# Ubuntu-based Docker image for GStreamer

Currently this project builds a Ubuntu 22.04 image with:

- GStreamer 1.22.2
- opencv and opencv_contrib 4.7.0
- dlib 19.24
- libnvrtc (from CUDA) 12

It relies on GStreamer [monorepo](https://gitlab.freedesktop.org/gstreamer/gstreamer) to build GStreamer and its plugins (in particular enabling `nvcodec`).

Motivations:

- possibility to choose GStreamer (latest) version
- `nvcodec` plugin is not installed (on Ubuntu) with `apt-get install gstreamer1.0-plugins-bad`
- includes opencv and dlib

### Preparation: download dependencies

Prepare `deps` folder to store source and binaries that will be used by the Dockerfile:

```
mkdir -p deps
cd deps
```

You will have to edit Dockerfile.ubuntu if you select different versions of opencv, dlib or nvrtc.

#### GStreamer

Download source and choose version:

```
git clone https://gitlab.freedesktop.org/gstreamer/gstreamer.git
cd gstreamer
git checkout 1.22.0
cd ../..
```

#### opencv

Download opencv and opencv_contrib src:

```
curl https://github.com/opencv/opencv/archive/refs/tags/4.7.0.zip -L --output deps/opencv.zip
```

```
curl https://github.com/opencv/opencv_contrib/archive/refs/tags/4.7.0.zip -L --output deps/opencv_contrib.zip
```

Then edit Dockerfiles `OPENCV_VERSION` env to the chosen version, `4.7.0` in the above example.

#### dlib

Download dlib src:

```
curl http://dlib.net/files/dlib-19.24.tar.bz2 --output deps/dlib.tar.bz2
```

#### nvrtc

libnvrtc.so is needed to enable `cudaconvert`, `cudascale `and `cudaconvertscale` GStreamer plugins.

In the following example we picked CUDA 11.7 that is compatible with the driver 525 of our GPU.

```
wget -P deps/ https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-nvrtc-dev-12-1_12.1.55-1_amd64.deb
```

```
wget -P deps/ https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-nvrtc-12-1_12.1.55-1_amd64.deb
```

You may pick another, looking at: https://developer.download.nvidia.com/compute/cuda/repos/<OS>/x86_64/

Alternatives to this handpicked nvrtc package installation are:

- install the whole CUDA toolkit (https://developer.nvidia.com/cuda-downloads for CUDA 12 or https://developer.nvidia.com/cuda-11-7-0-download-archive for CUDA 11.7)

- start from an nvidia/cuda devel image (rather than a bare ubuntu one), for instance nvidia/cuda:11.7.0-devel-ubuntu22.04 (`Dockerfile.ubuntu.cuda` is provided as an example)

### Build

First of all you may check (in the Dockerfile) that the meson build configuration options fit with your purpose (`-Dbuiltype` for instance). Available options are listed by `meson configure` (within a container). Build and run:

```
# from the root project folder

 docker build -f Dockerfile.gpu -t ubuntu22.04-gstreamer1.22.0 .
```

To build with image layers cache and save the output of the build you may alternatively run:

```
docker build --no-cache -f Dockerfile.gpu -t ubuntu22.04-gstreamer1.22.0 . 2>&1 | tee build.log
```

### Test container

Create a data folder (mounted as a volume in `docker run`) with an input.mkv file , run and enter container, then try nvcodec:

```
docker run --gpus all --rm -it ubuntu-gstreamer:latest /bin/bash
```

```
gst-launch-1.0 -e videotestsrc num-buffers=1000 ! video/x-raw,width=320,height=240 ! videoconvert ! queue ! nvh264enc ! h264parse ! splitmuxsink location=video%02d.mkv max-size-time=10000000000 muxer-factory=matroskamux muxer-properties='properties,streamable=true'
```

### Share image

Tag and push image if wanted

```
docker image tag ubuntu-gstreamer:latest <docker container storage>ubuntu-gstreamer:ubuntu22.04-gstreamer1.22.0
```

```
docker push <docker container storage>ubuntu-gstreamer:ubuntu22.04-gstreamer1.22.0
```

### Build from CUDA image

```
docker build -f Dockerfile.ubuntu.cuda -t ubuntu-cuda-gstreamer .
```

### Image build log sample

The meson configuration output ends by listing the enabled build targets, here is a sample of an output log:

```
Build targets in project: 493

libdv 1.0.0

    YUV format            : YUY2
    assembly optimizations: YES

gst-editing-services 1.22.0

    Plugins: nle, ges

gst-plugins-bad 1.22.0

    Plugins               : accurip, adpcmdec, adpcmenc, aiff, asfmux,
                            audiobuffersplit, audiofxbad, audiomixmatrix,
                            audiolatency, audiovisualizers, autoconvert, bayer,
                            camerabin, codecalpha, codectimestamper,
                            coloreffects, debugutilsbad, dvbsubenc,
                            dvbsuboverlay, dvdspu, faceoverlay, festival,
                            fieldanalysis, freeverb, frei0r, gaudieffects, gdp,
                            geometrictransform, id3tag, inter, interlace,
                            ivfparse, ivtc, jp2kdecimator, jpegformat, rfbsrc,
                            midi, mpegpsdemux, mpegpsmux, mpegtsdemux,
                            mpegtsmux, mxf, netsim, rtponvif, pcapparse, pnm,
                            proxy, legacyrawparse, removesilence, rist, rtmp2,
                            rtpmanagerbad, sdpelem, segmentclip, siren, smooth,
                            speed, subenc, switchbin, timecode, transcode,
                            videofiltersbad, videoframe_audiolevel,
                            videoparsersbad, videosignal, vmnc, y4mdec,
                            decklink, dvb, fbdevsink, ipcpipeline, nvcodec,
                            qsv, shm, va, aes, avtp, closedcaption, dash, dtls,
                            fdkaac, hls, iqa, microdns, opencv, opusparse,
                            sctp, smoothstreaming, sndfile, soundtouch,
                            ttmlsubs, webrtc
    (A)GPL license allowed: True

gst-plugins-base 1.22.0

    Plugins: adder, app, audioconvert, audiomixer, audiorate, audioresample,
             audiotestsrc, compositor, encoding, gio, overlaycomposition,
             pbtypes, playback, rawparse, subparse, tcp, typefindfunctions,
             videoconvertscale, videorate, videotestsrc, volume, ogg, opus,
             pango, vorbis, ximagesink

gst-plugins-good 1.22.0

    Plugins: alpha, alphacolor, apetag, audiofx, audioparsers, auparse,
             autodetect, avi, cutter, navigationtest, debug, deinterlace, dtmf,
             effectv, equalizer, flv, flxdec, goom, goom2k1, icydemux,
             id3demux, imagefreeze, interleave, isomp4, alaw, mulaw, level,
             matroska, monoscope, multifile, multipart, replaygain, rtp,
             rtpmanager, rtsp, shapewipe, smpte, spectrum, udp, videobox,
             videocrop, videofilter, videomixer, wavenc, wavparse, xingmux,
             y4menc, ossaudio, oss4, video4linux2, ximagesrc, adaptivedemux2,
             cairo, flac, jpeg, lame, dv, png, soup, vpx

gst-plugins-ugly 1.22.0

    Plugins               : asf, dvdlpcmdec, dvdsub, realmedia, x264
    (A)GPL license allowed: True

gst-rtsp-server 1.22.0

    Plugins: rtspclientsink

gstreamer 1.22.0

    Plugins: coreelements, coretracers

gstreamer-vaapi 1.22.0

    Plugins: vaapi

json-glib 1.6.6

  Directories
    prefix       : /gstreamer/install
    includedir   : /gstreamer/install/include
    libdir       : /gstreamer/install/lib/x86_64-linux-gnu
    datadir      : /gstreamer/install/share

  Build
    Introspection: YES
    Documentation: NO
    Manual pages : NO
    Tests        : YES

gstreamer-full 1.22.0

  Build options
    gstreamer-full library    : NO
    Tools                     : gst-inspect, gst-stats, gst-typefind,
                                gst-launch, gst-device-monitor, gst-discoverer,
                                gst-play, ges-launch

  Subprojects
    FFmpeg                    : YES
    avtp                      : YES
    dssim                     : YES
    dv                        : YES
    fdk-aac                   : YES
    gl-headers                : YES
    gst-devtools              : NO Feature 'devtools' disabled
    gst-editing-services      : YES
    gst-examples              : YES 3 warnings
    gst-integration-testsuites: NO Feature 'devtools' disabled
    gst-libav                 : YES
    gst-omx                   : NO Feature 'omx' disabled
    gst-plugins-bad           : YES 1 warnings
    gst-plugins-base          : YES 1 warnings
    gst-plugins-good          : YES 1 warnings
    gst-plugins-rs            : NO Feature 'rs' disabled
    gst-plugins-ugly          : YES
    gst-python                : NO
                                Subproject "subprojects/pygobject" required but not found.
    gst-rtsp-server           : YES
    gstreamer                 : YES 1 warnings
    gstreamer-sharp           : NO Feature 'sharp' disabled
    gstreamer-vaapi           : YES
    json-glib                 : YES 1 warnings
    lame                      : YES 1 warnings
    libdrm                    : NO
                                Dependency "pciaccess" not found, tried pkgconfig and cmake
    libjpeg-turbo             : YES
    libmicrodns               : YES
    libnice                   : YES
    libopenjp2                : NO
                                In subproject libopenjp2: Unknown options: "libopenjp2:build_codec"
    libpsl                    : YES
    libsoup                   : NO
                                Assert failed: libsoup requires glib-networking for TLS support
    libxml2                   : YES
    openh264                  : NO Program 'nasm' not found or not executable
    pygobject                 : NO
                                Dependency 'glib-2.0' is required but not found.
    sqlite3                   : YES
    tinyalsa                  : NO
                                Neither a subproject directory nor a tinyalsa.wrap file was found.
    x264                      : YES 1 warnings

  User defined options
    buildtype                 : release
    prefix                    : /gstreamer/install
    devtools                  : disabled
    doc                       : disabled
    examples                  : disabled
    gpl                       : enabled
    libav                     : enabled
    orc                       : disabled
    rs                        : disabled
    tests                     : disabled
    vaapi                     : enabled
    gst-plugins-base:pango    : enabled
    gst-plugins-ugly:x264     : enabled
    libsoup:sysprof           : disabled
```
