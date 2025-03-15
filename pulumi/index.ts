import * as proxmox from "@muhlba91/pulumi-proxmoxve";
import { VirtualMachine } from "@muhlba91/pulumi-proxmoxve/vm";
import { Config } from "@pulumi/pulumi";

const config = new Config();

const apiToken = config.requireSecret("proxmox_api_token");
const endpoint = config.requireSecret("proxmox_endpoint");

const provider = new proxmox.Provider('default', { endpoint, apiToken });

const talosControlPlane = new VirtualMachine("talos-control-plane", {
    name: "talos-control-plane",
    nodeName: "proxmox",
    poolId: "Kubernetes",
    tags: ["k8s", "pulumi", "cp"],
    cpu: {
        cores: 2,
        sockets: 1,
        type: "x86-64-v2-AES",
    },
    memory: {
        dedicated: 2048,
        floating: 2048
    },
    cdrom: {
        enabled: true,
        fileId: "local:iso/talos.iso"
    },
    disks: [{
        backup: true,
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
    onBoot: true,
    agent: {
        enabled: true
    }
}, {provider});

// FIXME Why [7][0] ?
export const vmIp = talosControlPlane.ipv4Addresses[7][0];