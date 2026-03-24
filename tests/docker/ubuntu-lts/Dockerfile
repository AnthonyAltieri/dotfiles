FROM ubuntu:24.04

SHELL ["/bin/bash", "-lc"]

ARG USERNAME=anthonyaltieri
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    xz-utils \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nix \
  && printf 'experimental-features = nix-command flakes\nsandbox = false\n' > /etc/nix/nix.conf

RUN useradd --create-home --shell /bin/bash "${USERNAME}" \
  && mkdir -p /nix \
  && chown "${USERNAME}:${USERNAME}" /nix

USER ${USERNAME}
ENV USER=${USERNAME}
ENV HOME=/home/${USERNAME}
ENV PATH=${HOME}/.nix-profile/bin:${HOME}/.local/state/nix/profile/bin:/usr/local/bin:/usr/bin:/bin

RUN curl -fsSL https://nixos.org/nix/install | bash -s -- --no-daemon \
  && . "${HOME}/.nix-profile/etc/profile.d/nix.sh" \
  && nix --version

WORKDIR /work

COPY --chown=${USERNAME}:${USERNAME} . /work

ENTRYPOINT ["/work/tests/docker/ubuntu-lts/run-profile-smoke-test.sh"]
