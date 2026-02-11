FROM rockylinux:8.8

RUN dnf -y update && \
    dnf -y install \
      bzip2 \
      ca-certificates \
      curl \
      file \
      findutils \
      gawk \
      gcc \
      gcc-c++ \
      git \
      gzip \
      make \
      patch \
      perl \
      python3 \
      python3-pip \
      tar \
      tcsh \
      which \
      xz && \
    dnf clean all && \
    rm -rf /var/cache/dnf

RUN curl -fsSL "https://micro.mamba.pm/api/micromamba/linux-64/latest" | tar -xj -C /tmp bin/micromamba && \
    install -m 0755 /tmp/bin/micromamba /usr/local/bin/micromamba && \
    rm -rf /tmp/bin

RUN pip3 install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir conda-pack

ENV MAMBA_ROOT_PREFIX=/opt/micromamba
WORKDIR /work

COPY docker/build_inside_container.sh /usr/local/bin/build_inside_container.sh
COPY docker/verify_bundle_inside_container.sh /usr/local/bin/verify_bundle_inside_container.sh
RUN chmod +x /usr/local/bin/build_inside_container.sh /usr/local/bin/verify_bundle_inside_container.sh

ENTRYPOINT ["/usr/local/bin/build_inside_container.sh"]
