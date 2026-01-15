FROM eclipse-temurin:25-jdk-alpine

LABEL maintainer="ketbome"
LABEL description="Hytale Dedicated Server"

# Dependencies
RUN apk add --no-cache bash dos2unix curl unzip

# Download hytale-downloader
RUN curl -L -o /tmp/hytale-downloader.zip https://downloader.hytale.com/hytale-downloader.zip && \
    unzip /tmp/hytale-downloader.zip -d /tmp/downloader && \
    mv /tmp/downloader/hytale-downloader-linux-amd64 /usr/local/bin/hytale-downloader && \
    chmod +x /usr/local/bin/hytale-downloader && \
    rm -rf /tmp/hytale-downloader.zip /tmp/downloader

# Non-root user
RUN addgroup -S hytale && adduser -S -G hytale hytale

ENV SERVER_HOME=/opt/hytale
ENV JAVA_XMS=4G
ENV JAVA_XMX=8G
ENV BIND_PORT=5520
ENV BIND_ADDR=0.0.0.0
ENV AUTO_DOWNLOAD=true

# JVM tuning
ENV USE_G1GC=true
ENV G1_NEW_SIZE_PERCENT=30
ENV G1_MAX_NEW_SIZE_PERCENT=40
ENV G1_HEAP_REGION_SIZE=8M
ENV MAX_GC_PAUSE_MILLIS=200

# Server config
ENV VIEW_DISTANCE=""
ENV MAX_PLAYERS=""
ENV SERVER_NAME=""

WORKDIR $SERVER_HOME

RUN mkdir -p universe mods logs config .cache && \
    chown -R hytale:hytale $SERVER_HOME

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN dos2unix /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/entrypoint.sh

USER hytale

EXPOSE 5520/udp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
