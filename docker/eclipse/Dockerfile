FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Berlin
ENV ECLIPSE_VERSION=2024-12
ENV ECLIPSE_BUILD=R
ENV ECLIPSE_PACKAGE=eclipse-java-${ECLIPSE_VERSION}-${ECLIPSE_BUILD}-linux-gtk-x86_64.tar.gz
ENV ECLIPSE_URL=https://ftp.halifax.rwth-aachen.de/eclipse/technology/epp/downloads/release/${ECLIPSE_VERSION}/${ECLIPSE_BUILD}/${ECLIPSE_PACKAGE}

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk \
    ca-certificates \
    wget \
    curl \
    xvfb \
    xfce4 \
    x11vnc \
    novnc \
    websockify \
    dbus-x11 \
    xterm \
    tigervnc-tools \
    procps \
    tzdata \
    rsync \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash developer
WORKDIR /opt
RUN wget -O /tmp/eclipse.tar.gz ${ECLIPSE_URL} \
    && tar -xzf /tmp/eclipse.tar.gz -C /opt \
    && rm /tmp/eclipse.tar.gz \
    && ln -s /opt/eclipse/eclipse /usr/local/bin/eclipse

COPY docker/eclipse/scripts/entrypoint.sh /entrypoint.sh
COPY docker/eclipse/scripts/backup-config.sh /usr/local/bin/backup-config.sh
COPY docker/eclipse/scripts/restore-config.sh /usr/local/bin/restore-config.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/backup-config.sh /usr/local/bin/restore-config.sh

USER developer
WORKDIR /home/developer

EXPOSE 6080
ENTRYPOINT ["/entrypoint.sh"]
