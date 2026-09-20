FROM debian:12-slim

# sudo is the one prerequisite bootstrap cannot install as an unprivileged user.
RUN apt-get update \
  && apt-get install -y --no-install-recommends sudo \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --create-home --shell /bin/bash dotfiles \
  && echo 'dotfiles ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/dotfiles \
  && mkdir -p /etc/nix \
  && printf 'experimental-features = nix-command flakes\nsandbox = false\n' > /etc/nix/nix.conf

USER dotfiles
ENV USER=dotfiles HOME=/home/dotfiles
WORKDIR /work
COPY --chown=dotfiles:dotfiles . /work

# Preview on a fresh machine must fail without installing prerequisites.
RUN for flag in --dry-run --diff; do \
      if ./bootstrap.sh personal "$flag" > /tmp/preview.log 2>&1; then exit 1; fi; \
      grep -q 'Preview mode cannot continue until Nix is already installed' /tmp/preview.log \
        && test ! -e /nix || exit 1; \
    done \
  && ./bootstrap.sh install-dependencies

ENTRYPOINT ["bash", "/work/tests/docker/debian/run-bootstrap-smoke-test.sh"]
