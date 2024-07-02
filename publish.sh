#!/bin/bash

set -e

archs=(amd64 s390x)
ARCH=$(uname -m | grep -q s390x && echo s390x || echo amd64)

export KUBEVIRTCI_TAG=$(date +"%y%m%d%H%M")-$(git rev-parse --short HEAD)
PREV_KUBEVIRTCI_TAG=$(curl -sL https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirtci/latest?ignoreCache=1)
BYPASS_PMAN=${BYPASS_PMAN:-false}
PHASES=${PHASES:-k8s}

function detect_cri() {
    if podman ps >/dev/null 2>&1; then echo podman; elif docker ps >/dev/null 2>&1; then echo docker; fi
}

TARGET_REPO="quay.io/kubevirtci"
TARGET_KUBEVIRT_REPO="quay.io/kubevirt"
TARGET_GIT_REMOTE="https://kubevirt-bot@github.com/kubevirt/kubevirtci.git"
export CRI_BIN=${CRI_BIN:-$(detect_cri)}

IMAGES_TO_BUILD=()
IMAGES_TO_RETAG=()

function run_provision_manager() {
  if [ $BYPASS_PMAN == true ]; then
      IMAGES_TO_BUILD="$(find cluster-provision/k8s/* -maxdepth 0 -type d -printf '%f\n')"
      echo "INFO: Provision manager bypassed, rebuilding all vm based providers"
      echo "IMAGES_TO_BUILD: $(echo ${IMAGES_TO_BUILD[@]})"
      return
  fi

  json_result=$(${CRI_BIN} run --rm -v $(pwd):/workdir:Z quay.io/kubevirtci/gocli-${ARCH} provision-manager)
  echo "INFO: Provision manager results: $json_result"

  while IFS=":" read key value; do
      if [[ "$value" == "true" ]]; then
          IMAGES_TO_BUILD+=("$key")
      else
          IMAGES_TO_RETAG+=("$key")
      fi
  done < <(echo "$json_result" | jq -r 'to_entries[] | "\(.key):\(.value)"')

  echo "IMAGES_TO_BUILD: ${IMAGES_TO_BUILD[@]}"
  echo "IMAGES_TO_RETAG: ${IMAGES_TO_RETAG[@]}"
}

function build_gocli() {
  (cd cluster-provision/gocli && make container)
  ${CRI_BIN} tag ${TARGET_REPO}/gocli-${ARCH} ${TARGET_REPO}/gocli-${ARCH}:${KUBEVIRTCI_TAG}
}

function build_centos9_base_image_with_deps() {
  (cd cluster-provision/centos9 && ./build.sh)
  IMAGE_TO_BUILD="$(find cluster-provision/k8s/* -maxdepth 0 -type d -printf '%f\n' | head -1)"
  (cd cluster-provision/k8s/${IMAGE_TO_BUILD} && ../provision.sh)
}

function build_clusters() {
  for i in ${IMAGES_TO_BUILD[@]}; do
    if [ $ARCH != "s390x" ]; then
      echo "INFO: building $i"
      cluster-provision/gocli/build/cli provision --phases k8s cluster-provision/k8s/$i
      ${CRI_BIN} tag ${TARGET_REPO}/k8s-$i ${TARGET_REPO}/k8s-$i-${ARCH}:${KUBEVIRTCI_TAG}

      cluster-provision/gocli/build/cli provision --phases k8s cluster-provision/k8s/$i --slim
      ${CRI_BIN} tag ${TARGET_REPO}/k8s-$i ${TARGET_REPO}/k8s-$i-${ARCH}:${KUBEVIRTCI_TAG}-slim
    elif [ $ARCH == "s390x" ] && [ $i == "1.28" ]; then
      echo "INFO: building $i slim"
      cluster-provision/gocli/build/cli provision --phases k8s cluster-provision/k8s/$i --slim
      ${CRI_BIN} tag ${TARGET_REPO}/k8s-$i ${TARGET_REPO}/k8s-$i-${ARCH}:${KUBEVIRTCI_TAG}-slim
    fi
  done
}

function push_node_base_image() {
  TARGET_IMAGE="${TARGET_REPO}/centos9-${ARCH}:${KUBEVIRTCI_TAG}"
  podman tag ${TARGET_REPO}/centos9-base:latest ${TARGET_IMAGE}
  echo "INFO: push $TARGET_IMAGE"
  podman push ${TARGET_IMAGE}
  echo ${TARGET_IMAGE} > cluster-provision/k8s/base-image
}

function push_cluster_images() {
  for i in ${IMAGES_TO_BUILD[@]}; do
    if [ $ARCH != "s390x" ]; then
      echo "INFO: push $i"
      TARGET_IMAGE="${TARGET_REPO}/k8s-$i-${ARCH}:${KUBEVIRTCI_TAG}"
      podman push "$TARGET_IMAGE"

      TARGET_IMAGE="${TARGET_REPO}/k8s-$i-${ARCH}:${KUBEVIRTCI_TAG}-slim"
      podman push "$TARGET_IMAGE"
    elif [ $ARCH == "s390x" ] && [ $i == "1.28" ]; then
      echo "INFO: push $i slim"
      TARGET_IMAGE="${TARGET_REPO}/k8s-$i-${ARCH}:${KUBEVIRTCI_TAG}-slim"
      podman push "$TARGET_IMAGE"
    fi
  done

  # images that the change doesn't affect can be retagged from previous tag
  for i in ${IMAGES_TO_RETAG[@]}; do
    echo "INFO: retagging $i (previous tag $PREV_KUBEVIRTCI_TAG)"
    skopeo copy "docker://${TARGET_REPO}/k8s-$i-${ARCH}:${PREV_KUBEVIRTCI_TAG}" "docker://${TARGET_REPO}/k8s-$i-${ARCH}:${KUBEVIRTCI_TAG}"
    skopeo copy "docker://${TARGET_REPO}/k8s-$i-${ARCH}:${PREV_KUBEVIRTCI_TAG}-slim" "docker://${TARGET_REPO}/k8s-$i-${ARCH}:${KUBEVIRTCI_TAG}-slim"
  done
}

function push_gocli() {
  echo "INFO: push gocli-${ARCH}"
  TARGET_IMAGE="${TARGET_REPO}/gocli-${ARCH}:${KUBEVIRTCI_TAG}"
  podman push "$TARGET_IMAGE"
}

function publish_node_base_image() {
  build_centos9_base_image_with_deps
  push_node_base_image
}

function publish_clusters() {
  build_clusters
  push_cluster_images
}

function build_alpine_container_disk() {
  echo "INFO: build alpine container disk"
  (cd cluster-provision/images/vm-image-builder && ./create-containerdisk.sh alpine-cloud-init)
  ${CRI_BIN} tag alpine-cloud-init:devel ${TARGET_REPO}/alpine-with-test-tooling-container-disk:${KUBEVIRTCI_TAG}
  ${CRI_BIN} tag alpine-cloud-init:devel ${TARGET_KUBEVIRT_REPO}/alpine-with-test-tooling-container-disk:devel
}

function push_alpine_container_disk() {
  echo "INFO: push alpine container disk"
  TARGET_IMAGE="${TARGET_REPO}/alpine-with-test-tooling-container-disk:${KUBEVIRTCI_TAG}"
  podman push $TARGET_IMAGE
  TARGET_KUBEVIRT_IMAGE="${TARGET_KUBEVIRT_REPO}/alpine-with-test-tooling-container-disk:devel"
  podman push $TARGET_KUBEVIRT_IMAGE
}

function publish_alpine_container_disk() {
  build_alpine_container_disk
  push_alpine_container_disk
}

function create_git_tag() {
  if [ "$CI" == "true" ]; then
    git config user.name "kubevirt-bot"
    git config user.email "kubevirtbot@redhat.com"
  fi

  echo "INFO: push new tag $KUBEVIRTCI_TAG"
  git tag ${KUBEVIRTCI_TAG}
  git push ${TARGET_GIT_REMOTE} ${KUBEVIRTCI_TAG}
}

publish_manifest() {
  if [ $ARCH != "s390x" ]; then
    local amend
    local image_name="${1:?}"
    local image_tag="${2:?}"
    local full_image_name="${TARGET_REPO}/${image_name}:${image_tag}"
    amend=""
    for arch in ${archs[*]};do
        amend+=" --amend ${TARGET_REPO}/${image_name}-${arch}:${image_tag}"
    done
    podman manifest create ${full_image_name} ${amend}
    podman manifest push ${full_image_name} "docker://${full_image_name}"
  fi
}

function main() {
  if [ "$PHASES" == "linux" ]; then
    publish_node_base_image
    publish_manifest "centos9" $KUBEVIRTCI_TAG
    exit 0
  fi
  build_gocli
  run_provision_manager
  publish_clusters
  for i in ${IMAGES_TO_BUILD[@]}; do
    if [ $ARCH != "s390x" ]; then
      echo "INFO: publish manifests of $i"
      publish_manifest k8s-$i $KUBEVIRTCI_TAG
      publish_manifest k8s-$i ${KUBEVIRTCI_TAG}-slim
    elif [ $ARCH == "s390x" ] && [ $i == "1.28" ]; then
      echo "INFO: publish manifest of $i slim"
      publish_manifest k8s-$i ${KUBEVIRTCI_TAG}-slim
    fi
  done
  publish_alpine_container_disk
  push_gocli
  publish_manifest "gocli" $KUBEVIRTCI_TAG
  create_git_tag
}

main "$@"
