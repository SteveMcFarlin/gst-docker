## Notes  - All library or executable depencences that need to be in the final image
##          should be added in install-dependencies.sh
##
##
## TODO:  - There are duplicates between install-dependencies.sh and the files installed 
##          via RUN apt-get install
##        - The Gstreamer build should be customized to build only what we need
##
FROM ubuntu:22.04 AS base
SHELL ["/bin/bash", "--login", "-c"]
ENV DEBIAN_FRONTEND noninteractive

COPY scripts/install-dependencies.sh /
RUN ["/install-dependencies.sh"]
RUN rm /install-dependencies.sh

COPY fonts /fonts
RUN ls /fonts
RUN ["/fonts/install-averta-family.sh"]
RUN rm -rf /fonts

WORKDIR /install/cuda

RUN apt-get update &&\
  apt-get install --no-install-recommends -y wget &&\
  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-nvrtc-dev-12-1_12.1.55-1_amd64.deb &&\
  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-nvrtc-12-1_12.1.55-1_amd64.deb &&\
  apt-get install --no-install-recommends ./cuda-nvrtc-12-1_12.1.55-1_amd64.deb &&\
  apt-get install --no-install-recommends ./cuda-nvrtc-dev-12-1_12.1.55-1_amd64.deb &&\
  rm ./cuda*.deb &&\
  apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /
RUN rm -R /install

FROM base AS build

COPY scripts/install-build-deps.sh /
RUN ["/install-build-deps.sh"]
RUN rm /install-build-deps.sh

FROM build as open-cv

# build opencv https://docs.opencv.org/4.x/d7/d9f/tutorial_linux_install.html
WORKDIR /install/opencv

### Install OpenCV
## COPY deps/opencv.zip deps/opencv_contrib.zip ./
# RUN curl https://github.com/opencv/opencv/archive/refs/tags/4.7.0.zip -L --output opencv.zip
# RUN curl https://github.com/opencv/opencv_contrib/archive/refs/tags/4.7.0.zip -L --output opencv_contrib.zip

# RUN unzip opencv.zip
# RUN unzip opencv_contrib.zip
# RUN mkdir -p build

# WORKDIR /install/opencv/build
# RUN cmake -DOPENCV_GENERATE_PKGCONFIG=ON -DOPENCV_EXTRA_MODULES_PATH=../opencv_contrib-4.7.0/modules/ ../opencv-4.7.0/
# RUN cmake --build .
# RUN make install

FROM build as rust

ENV RUST_VERSION=1.76.0
ENV GSTREAMER_VERSION=1.24.1

## Disabling rust for now as we are not using any of the plugins that require it
# Install Rust
# WORKDIR /install/rust
# RUN wget -O- https://sh.rustup.rs | /bin/bash -s -- -y --default-toolchain ${RUST_VERSION}
# ENV PATH="/root/.cargo/bin:${PATH}"
# RUN cargo install cargo-c
# RUN rustc --version

FROM rust as gstreamer

WORKDIR /install

RUN git clone https://gitlab.freedesktop.org/gstreamer/gstreamer.git

WORKDIR /install/gstreamer

RUN git checkout ${GSTREAMER_VERSION}
RUN meson --prefix=/opt/gstreamer \
  -Dgpl=enabled \
  -Dvaapi=enabled \
  -Drs=disabled \
  -Dlibav=enabled \
  -Dgood=enabled \
  -Dbad=enabled \
  -Dugly=enabled \
  -Dges=enabled \
  -Drtsp_server=enabled \
  -Dbase=enabled \
  -Dlibnice=enabled \
  -Ddevtools=disabled \
  -Dtests=disabled \
  -Dexamples=disabled \
  -Ddoc=disabled \
  -Dorc=disabled \
  -Dlibsoup:sysprof=disabled \
  -Dbuildtype=release build

RUN ninja -C build
RUN meson install -C build

## This is if we need a specific plugin that is not in the main gstreamer repo
## rust plugins dir: /opt/gstreamer/lib/x86_64-linux-gnu/gstreamer-1.0
# COPY --from=gstreamer-builder /gstreamer/install /opt/gstreamer
# WORKDIR /install
# RUN git clone https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git
# WORKDIR /install/gst-plugins-rs
# RUN git checkout gstreamer-${GSTREAMER_VERSION}
# RUN cargo cbuild -p gst-plugin-inter --release --prefix=/gstreamer/install --libdir /gstreamer/install/lib/$(uname -m)-linux-gnu/gstreamer-1.0
# RUN cargo cinstall -p gst-plugin-inter --release --prefix=/gstreamer/install --libdir /gstreamer/install/lib/$(uname -m)-linux-gnu/gstreamer-1.0

WORKDIR /install

ADD plugins/ ./plugins/
COPY scripts/compile-gstcef.sh ./
COPY scripts/compile-gstperf.sh ./
COPY scripts/compile-gstinterpipe.sh ./
RUN ["./compile-gstcef.sh"]
RUN ["./compile-gstperf.sh"]
RUN ["./compile-gstinterpipe.sh"]


FROM build as dlib

WORKDIR /install/dlib

RUN curl http://dlib.net/files/dlib-19.24.tar.bz2 --output dlib.tar.bz2

RUN mkdir -p /dlib/src/build /dlib/install
RUN tar -xvf ./dlib.tar.bz2 -C . --strip-components 1

WORKDIR /install/dlib/build
RUN cmake -GNinja \
  -DCMAKE_INSTALL_PREFIX:PATH=/dlib/install \
  -DCMAKE_INSTALL_LIBDIR:PATH=/dlib/install/lib \
  -DBUILD_SHARED_LIBS=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_SSE2_INSTRUCTIONS=ON \
  -DUSE_SSE4_INSTRUCTIONS=ON \
  -DUSE_AVX_INSTRUCTIONS=ON \
  -DDLIB_USE_CUDA=OFF \
  ".."
RUN ninja
RUN ninja install

FROM base AS final

COPY xorg.conf /etc/X11/xorg.conf
COPY --from=gstreamer /opt/gstreamer /opt/gstreamer
COPY --from=dlib /dlib/install /opt/dlib

ENV PATH="${PATH}:/opt/gstreamer/bin"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/opt/gstreamer/lib/x86_64-linux-gnu:/opt/dlib/lib:/usr/local/cuda-12.1/lib64"
ENV LIBRARY_PATH="${LIBRARY_PATH}:/opt/gstreamer/lib/x86_64-linux-gnu:/opt/dlib/lib:/usr/local/cuda-12.1/lib64"
ENV PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:/opt/gstreamer/lib/x86_64-linux-gnu/pkgconfig:/opt/dlib/lib/pkgconfig"
ENV CPLUS_INCLUDE_PATH="${CPLUS_INCLUDE_PATH}:/opt/gstreamer/include/gstreamer-1.0:/opt/dlib/include"
ENV GST_PLUGIN_PATH=/opt/gstreamer/lib/x86_64-linux-gnu/gstreamer-1.0
ENV GST_PLUGIN_SCANNER=/opt/gstreamer/libexec/gstreamer-1.0/gst-plugin-scanner
ENV PYTHONPATH=/opt/gstreamer/lib/python3.10/site-packages
ENV GI_TYPELIB_PATH=/opt/gstreamer/lib/x86_64-linux-gnu/girepository-1.0/
ENV NVIDIA_DRIVER_CAPABILITIES all
ENV NVIDIA_VISIBLE_DEVICES all
ENV C_INCLUDE_PATH=/opt/gstreamer/include/gstreamer-1.0:/opt/gstreamer/include:/opt/gstreamer/include/gstreamer-1.0/gst

