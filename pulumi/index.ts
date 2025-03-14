import * as proxmox from "@muhlba91/pulumi-proxmoxve";
import { Config } from "@pulumi/pulumi";

const config = new Config();

const apiToken = config.requireSecret("proxmox_api_token");
const endpoint = config.requireSecret("proxmox_endpoint");

const provider = new proxmox.Provider('proxmoxve', { endpoint, apiToken });

proxmox.vm.getVirtualMachine({vmId: 101, nodeName: 'proxmox'}, {provider}).then(value => console.log({value}));
