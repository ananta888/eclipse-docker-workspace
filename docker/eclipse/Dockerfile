FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Berlin
ENV ECLIPSE_VERSION=2025-12
ENV ECLIPSE_BUILD=R
ENV ECLIPSE_PACKAGE=eclipse-java-${ECLIPSE_VERSION}-${ECLIPSE_BUILD}-linux-gtk-x86_64.tar.gz
ENV ECLIPSE_URL=https://www.eclipse.org/downloads/download.php?file=/technology/epp/downloads/release/${ECLIPSE_VERSION}/${ECLIPSE_BUILD}/${ECLIPSE_PACKAGE}&r=1

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
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Make noVNC root URL serve the client directly.
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

RUN useradd -ms /bin/bash developer

WORKDIR /opt
RUN wget --max-redirect=20 -O /tmp/eclipse.tar.gz "$ECLIPSE_URL" \
    && tar -xzf /tmp/eclipse.tar.gz -C /opt \
    && rm /tmp/eclipse.tar.gz \
    && ln -s /opt/eclipse/eclipse /usr/local/bin/eclipse

RUN /opt/eclipse/eclipse -nosplash \
    -application org.eclipse.equinox.p2.director \
    -repository "https://www.saros-project.org/update-site/eclipse,https://download.eclipse.org/releases/${ECLIPSE_VERSION}" \
    -installIU "saros.feature.feature.group" \
    -profile SDKProfile \
    -destination /opt/eclipse \
    -bundlepool /opt/eclipse \
    -roaming

COPY docker/eclipse/scripts/entrypoint.sh /entrypoint.sh
COPY docker/eclipse/scripts/backup-config.sh /usr/local/bin/backup-config.sh
COPY docker/eclipse/scripts/restore-config.sh /usr/local/bin/restore-config.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/backup-config.sh /usr/local/bin/restore-config.sh

USER root
WORKDIR /home/developer

EXPOSE 6080
ENTRYPOINT ["/entrypoint.sh"]
