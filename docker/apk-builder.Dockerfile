FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TZ=UTC

RUN apt-get update && apt-get install -y \
    bash \
    ca-certificates \
    curl \
    file \
    git \
    libglu1-mesa \
    openjdk-17-jdk \
    unzip \
    xz-utils \
    zip \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
ENV FLUTTER_HOME=/opt/flutter
ENV PATH=/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/build-tools/34.0.0:${PATH}

RUN mkdir -p /opt/android-sdk/cmdline-tools /opt/downloads

RUN curl -fsSL \
    https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip \
    -o /opt/downloads/android-cmdline-tools.zip \
    && unzip -q /opt/downloads/android-cmdline-tools.zip -d /opt/android-sdk/cmdline-tools \
    && mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest

RUN curl -fsSL \
    https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.41.6-stable.tar.xz \
    -o /opt/downloads/flutter.tar.xz \
    && tar -xJf /opt/downloads/flutter.tar.xz -C /opt

RUN yes | sdkmanager --licenses >/dev/null

RUN sdkmanager \
    "platform-tools" \
    "platforms;android-34" \
    "platforms;android-36" \
    "build-tools;34.0.0" \
    "build-tools;28.0.3" \
    "cmake;3.22.1" \
    "ndk;28.2.13676358"

RUN flutter config --no-analytics \
    && flutter precache --android

WORKDIR /workspace

CMD ["/bin/bash"]
