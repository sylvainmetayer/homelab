#!/usr/bin/env bash

mkdir -p external_templates

urls=()

urls=(
"https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/refs/tags/v8.2.1/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml"
"https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/refs/tags/v8.2.1/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml"
"https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/refs/tags/v8.2.1/client/config/crd/groupsnapshot.storage.k8s.io_volumegroupsnapshotclasses.yaml"
"https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/refs/tags/v8.2.1/client/config/crd/groupsnapshot.storage.k8s.io_volumegroupsnapshotcontents.yaml"
"https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/refs/tags/v8.2.1/client/config/crd/groupsnapshot.storage.k8s.io_volumegroupsnapshots.yaml"
"https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/refs/tags/v8.2.1/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml"
"https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/refs/tags/v8.2.1/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml"
"https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/refs/tags/v8.2.1/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml"
)

for url in "${urls[@]}"; do
    curl -sSL $url -o external_templates/$(basename $url)
done
