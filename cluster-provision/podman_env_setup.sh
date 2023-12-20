export CONTAINER_RUNTIME=podman
systemctl start --user podman.socket
export CONTAINER_HOST=unix:///run/podman/podman.sock
systemctl enable --now podman.socket
