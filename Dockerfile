# 设置 BuildKit SBOM（Software Bill of Materials）扫描上下文为启用状态，用于生成软件物料清单。
ARG BUILDKIT_SBOM_SCAN_CONTEXT=true

# 设置编译镜像版本
# 这个是原作者预先构建的编译镜像
# 版本查看地址 https://hub.docker.com/r/gotify/build
ARG GO_VERSION=1.26.0

# 前端的部分需要提前构建
FROM --platform=${BUILDPLATFORM} docker.code.firfe.work/gotify/build:${GO_VERSION}-linux-${TARGETARCH} AS builder

ARG BUILDPLATFORM
ARG TARGETPLATFORM

# 设置国内镜像源
RUN go env -w GOPROXY=https://mirrors.aliyun.com/goproxy/,direct
RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list 2>/dev/null && \
    sed -i 's|security.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's|security.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list 2>/dev/null

ARG RUN_TESTS=0 # 0=never, 1=native only
ARG LD_FLAGS=""
ENV DEBIAN_FRONTEND=noninteractive
ENV VERSION=3.0.0

RUN apt-get update -o Acquire::AllowInsecureRepositories=true && \
    apt-get install -y --allow-unauthenticated \
    ca-certificates git&& \
    rm -rf /var/lib/apt/lists/*

COPY ./代码 /src/gotify

RUN cd /src/gotify && \
    if [ "$RUN_TESTS" = "1" ] && [ "$BUILDPLATFORM" = "$TARGETPLATFORM" ]; then \
    go test -v ./...; \
    fi && \
    LD_FLAGS=${LD_FLAGS} make OUTPUT=/target/app/gotify-app _build_within_docker

# 最终镜像
FROM docker.code.firfe.work/debian:13.5-slim

# 设置国内镜像源 - 适配 Debian 13 (trixie) slim 镜像
RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list 2>/dev/null && \
    sed -i 's|security.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's|security.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list 2>/dev/null

ARG GOTIFY_SERVER_EXPOSE=80
ENV GOTIFY_SERVER_PORT=$GOTIFY_SERVER_EXPOSE

WORKDIR /app

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update -o Acquire::AllowInsecureRepositories=true && \
    apt-get install -y --allow-unauthenticated \
    tzdata curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s CMD curl --fail http://localhost:$GOTIFY_SERVER_PORT/health || exit 1
EXPOSE $GOTIFY_SERVER_EXPOSE

COPY --from=builder /target /

ENTRYPOINT ["./gotify-app"]
CMD ["serve"] 
