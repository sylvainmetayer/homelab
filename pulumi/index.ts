import * as proxmox from "@muhlba91/pulumi-proxmoxve";
import * as pulumi from "@pulumi/pulumi";
import { VirtualMachine, VirtualMachineArgs } from "@muhlba91/pulumi-proxmoxve/vm";
import { Config, Output } from "@pulumi/pulumi";
import * as talos from "@pulumiverse/talos";
import * as yaml from 'js-yaml';
import { readFileSync } from 'fs';
import { ConfigurationApplyArgs, GetConfigurationOutputArgs } from "@pulumiverse/talos/machine";

// support for async/await : https://github.com/pulumi/pulumi/issues/5161#issuecomment-1010018506
const config = new Config();

const apiToken = config.requireSecret("proxmox_api_token");
const endpoint = config.requireSecret("proxmox_endpoint");

const provider = new proxmox.Provider('default', { endpoint, apiToken });

// https://factory.talos.dev/?arch=amd64&cmdline-set=true&extensions=-&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Fqemu-guest-agent&platform=nocloud&target=cloud&version=1.9.5
const schematicId = "dc7b152cb3ea99b821fcb7340ce7168313ce393d663740b791c36f6e95fc8586";
const talosVersion = "1.9.5";

const url = await talos.imagefactory.getUrls({ schematicId, talosVersion, platform: "nocloud" })
const talosIso = new proxmox.download.File("talos", { datastoreId: "local", url: url.urls.iso, nodeName: "proxmox", fileName: "talos-ext.iso", contentType: "iso" }, { provider });

const hardwareRequirements: Partial<VirtualMachineArgs> = {
    cpu: {
        cores: 2,
        sockets: 1,
        type: "x86-64-v2-AES",
    },
    memory: {
        dedicated: 4096,
        floating: 4096
    },
    cdrom: {
        enabled: true,
        fileId: pulumi.interpolate`${talosIso.datastoreId}:${talosIso.contentType}/${talosIso.fileName}`,
    },
    disks: [{
        speed: {
            iopsRead: 0,
            iopsReadBurstable: 0,
            iopsWrite: 0,
            iopsWriteBurstable: 0,
            read: 0,
            readBurstable: 0,
            write: 0,
            writeBurstable: 0
        },
        interface: "scsi0",
        datastoreId: "local-lvm",
        fileFormat: "raw",
        size: 32,
    }],
    networkDevices: [{
        enabled: true,
        bridge: "vmbr0",
        model: "virtio",
        firewall: true
    }],
}

const talosControlPlane = new VirtualMachine("talos-control-plane", {
    name: "talos-control-plane",
    nodeName: "proxmox",
    poolId: "Kubernetes",
    tags: ["k8s", "pulumi", "cp"],
    ...hardwareRequirements,
    onBoot: true,
    agent: {
        enabled: true
    }
}, { provider, ignoreChanges: ["disks[0].speed"] });

const talosCompute = new VirtualMachine("talos-compute-01", {
    name: "talos-compute-01",
    nodeName: "proxmox",
    poolId: "Kubernetes",
    tags: ["k8s", "pulumi", "compute"],
    ...hardwareRequirements,
    onBoot: true,
    agent: {
        enabled: true
    }
}, { provider, ignoreChanges: ["disks[0].speed"] });


// TALOS
const talosSecrets = new talos.machine.Secrets("homelab", { talosVersion }, { dependsOn: [talosCompute, talosControlPlane] });

// TODO filter empty, remove 127.0.0.1
// FIXME Why [7][0] ?;

export const controlPlaneIp = talosControlPlane.ipv4Addresses[7][0];
export const computeIp = talosCompute.ipv4Addresses[7][0];

const nodes = [controlPlaneIp, computeIp];

const talosConfiguration = talos.client.getConfigurationOutput({
    clusterName: "homelab",
    endpoints: [pulumi.interpolate`${controlPlaneIp}`],
    nodes,
    clientConfiguration: talosSecrets.clientConfiguration
}, { dependsOn: [talosCompute, talosControlPlane] });

const commonConfig: Omit<GetConfigurationOutputArgs, "machineType"> = {
    clusterName: "homelab",
    clusterEndpoint: pulumi.interpolate`https://${controlPlaneIp}:6443`,
    machineSecrets: talosSecrets.machineSecrets,
    talosVersion
}

const controlPlaneMachineConfiguration = talos.machine.getConfigurationOutput({
    ...commonConfig,
    machineType: "controlplane",
}, { dependsOn: [talosCompute, talosControlPlane] });

const workerMachineConfiguration = talos.machine.getConfigurationOutput({
    ...commonConfig,
    machineType: "worker"
}, { dependsOn: [talosCompute, talosControlPlane] });

const configurationApply = (filename: 'control-plane' | 'worker-config'): Omit<ConfigurationApplyArgs, "node" | "machineConfigurationInput"> => ({
    configPatches: [
        JSON.stringify(
            yaml.load(
                readFileSync(`config/${filename}.yaml`, { encoding: 'utf-8' })
            )
        )
    ],
    clientConfiguration: talosSecrets.clientConfiguration
});

const controlPlaneConfigurationApply = new talos.machine.ConfigurationApply("controlPlaneConfigurationApply", {
    ...configurationApply("control-plane"),
    node: controlPlaneIp,
    machineConfigurationInput: controlPlaneMachineConfiguration.machineConfiguration
}, { dependsOn: [talosControlPlane, talosCompute] });

const workerConfigurationApply = new talos.machine.ConfigurationApply("workerConfigurationApply", {
    ...configurationApply("worker-config"),
    node: computeIp,
    machineConfigurationInput: workerMachineConfiguration.machineConfiguration
}, { dependsOn: [talosControlPlane, talosCompute] });

const controlPlaneBootstrap = new talos.machine.Bootstrap("controlPlaneBoostrap", {
    node: controlPlaneIp,
    clientConfiguration: talosSecrets.clientConfiguration
}, { dependsOn: controlPlaneConfigurationApply });


const workerBootstrap = new talos.machine.Bootstrap("workerBoostrap", {
    node: computeIp,
    clientConfiguration: talosSecrets.clientConfiguration
}, { dependsOn: [workerConfigurationApply, controlPlaneConfigurationApply] });

export const talosConfig = talosConfiguration.talosConfig;

// https://www.pulumi.com/registry/packages/talos/api-docs/cluster/getkubeconfig/
// https://www.pulumi.com/registry/packages/flux/api-docs/fluxbootstrapgit/
// https://kubernetes.github.io/ingress-nginx/examples/auth/oauth-external-auth/