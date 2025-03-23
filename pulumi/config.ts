import { VirtualMachineArgs } from '@muhlba91/pulumi-proxmoxve/vm';
import { Output } from '@pulumi/pulumi';

export const macIpMapping = {
    controlPlane: [
        { macAddress: "44:6F:6D:60:00:01", ip: "192.168.1.201" },
        //{ macAddress: "44:6F:6D:60:00:02", ip: "192.168.1.202" },
        //{ macAddress: "44:6F:6D:60:00:03", ip: "192.168.1.203" },
    ],
    worker: [
        { macAddress: "44:6F:6D:60:00:04", ip: "192.168.1.211" },
        { macAddress: "44:6F:6D:60:00:05", ip: "192.168.1.212" },
        { macAddress: "44:6F:6D:60:00:06", ip: "192.168.1.213" }
    ]
}

const getHardwareRequirements = (fileId: Output<string>, macAddress: string): Partial<VirtualMachineArgs> => ({
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
        fileId,
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
        firewall: true,
        macAddress
    }],
});

export const commonVmParams = (fileId: Output<string>, macAddress: string) => ({
    ...getHardwareRequirements(
        fileId,
        macAddress
    ),
    nodeName: "proxmox",
    poolId: "Kubernetes",
    onBoot: true,
    agent: {
        enabled: true
    },
    started: true,
});

