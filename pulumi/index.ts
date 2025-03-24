import * as proxmox from "@muhlba91/pulumi-proxmoxve";
import * as pulumi from "@pulumi/pulumi";
import { VirtualMachine, VirtualMachineArgs } from "@muhlba91/pulumi-proxmoxve/vm";
import { Config, Output } from "@pulumi/pulumi";
import * as talos from "@pulumiverse/talos";
import * as yaml from 'js-yaml';
import { existsSync, readFileSync, writeFileSync } from 'fs';
import { ConfigurationApplyArgs, GetConfigurationOutputArgs } from "@pulumiverse/talos/machine";
import { commonVmParams, macIpMapping } from "./config";
import { Bootstrap } from "@pulumiverse/talos/machine/bootstrap";
import { CertRequest, LocallySignedCert, PrivateKey, SelfSignedCert } from "@pulumi/tls";
import { RepositoryDeployKey } from "@pulumi/github";
import * as flux from "@worawat/flux";
import { homedir } from "os";
import * as k8s from "@pulumi/kubernetes";

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

const vmIpDefinitions = macIpMapping;

const controlPlanes: Array<{ ip: string, vm: VirtualMachine }> = [];
const computeNodes: Array<{ ip: string, vm: VirtualMachine }> = [];

vmIpDefinitions.controlPlane.forEach((element, i) => {
    i = i + 1;
    const name = `talos-control-plane-${i}`;
    const vm = new VirtualMachine(name, {
        name,
        tags: ["k8s", "pulumi", "cp"],
        ...commonVmParams(
            pulumi.interpolate`${talosIso.datastoreId}:${talosIso.contentType}/${talosIso.fileName}`,
            element.macAddress
        )

    }, { provider, ignoreChanges: ["disks[0].speed"] });
    controlPlanes.push({ ip: element.ip, vm });
});

vmIpDefinitions.worker.forEach((element, i) => {
    i = i + 1;
    const name = `talos-compute-${i}`;
    const vm = new VirtualMachine(name, {
        name,
        tags: ["k8s", "pulumi", "compute"],
        ...commonVmParams(
            pulumi.interpolate`${talosIso.datastoreId}:${talosIso.contentType}/${talosIso.fileName}`,
            element.macAddress
        )
    }, { provider, ignoreChanges: ["disks[0].speed"] });
    computeNodes.push({ ip: element.ip, vm });
});

// TALOS

const vmDependsOn = [...controlPlanes.map(i => i.vm), ...computeNodes.map(i => i.vm)];
const clusterEndpoint = vmIpDefinitions.controlPlane[0].ip;

const talosSecrets = new talos.machine.Secrets("homelab", { talosVersion }, { dependsOn: vmDependsOn });

const talosConfiguration = talos.client.getConfigurationOutput({
    clusterName: "homelab",
    endpoints: vmIpDefinitions.controlPlane.map(i => i.ip),
    nodes: vmIpDefinitions.controlPlane.map(i => i.ip).concat(vmIpDefinitions.worker.map(i => i.ip)),
    clientConfiguration: talosSecrets.clientConfiguration
}, { dependsOn: vmDependsOn });

const commonConfig: Omit<GetConfigurationOutputArgs, "machineType"> = {
    clusterName: "homelab",
    clusterEndpoint: `https://${clusterEndpoint}:6443`,
    machineSecrets: talosSecrets.machineSecrets,
    talosVersion
}

const controlPlaneMachineConfiguration = talos.machine.getConfigurationOutput({
    ...commonConfig,
    machineType: "controlplane",
}, { dependsOn: vmDependsOn });

const workerMachineConfiguration = talos.machine.getConfigurationOutput({
    ...commonConfig,
    machineType: "worker"
}, { dependsOn: vmDependsOn });

const boostrapDependsOn: Bootstrap[] = [];
vmIpDefinitions.controlPlane.forEach((item, i) => {
    i = i + 1;
    const suffix = `control-plane-${i}`;
    const controlPlaneConfigurationApply = new talos.machine.ConfigurationApply(`talos-config-${suffix}`, {
        configPatches: [
            JSON.stringify(
                yaml.load(
                    readFileSync(`config/control-plane.yaml`, { encoding: 'utf-8' }).replace("{HOSTNAME}", `homelab-cp-${i}`).replace("{IP}", item.ip)
                )
            )
        ],
        clientConfiguration: talosSecrets.clientConfiguration,
        node: item.ip,
        machineConfigurationInput: controlPlaneMachineConfiguration.machineConfiguration
    }, { dependsOn: vmDependsOn });

    const controlPlaneBootstrap = new talos.machine.Bootstrap(`talos-boostrap-${suffix}`, {
        node: item.ip,
        clientConfiguration: talosSecrets.clientConfiguration
    }, { dependsOn: controlPlaneConfigurationApply });
    boostrapDependsOn.push(controlPlaneBootstrap);
});

vmIpDefinitions.worker.forEach((item, i) => {
    i = i + 1;
    const suffix = `worker-${i}`;
    const controlPlaneConfigurationApply = new talos.machine.ConfigurationApply(`talos-config-${suffix}`, {
        configPatches: [
            JSON.stringify(
                yaml.load(
                    readFileSync(`config/worker-config.yaml`, { encoding: 'utf-8' }).replace("{HOSTNAME}", `homelab-wo-${i}`).replace("{IP}", item.ip)
                )
            )
        ],
        clientConfiguration: talosSecrets.clientConfiguration,
        node: item.ip,
        machineConfigurationInput: workerMachineConfiguration.machineConfiguration
    }, { dependsOn: vmDependsOn });

    // Trust me, they are already boostraped. Eventually uncomment this if needed.
    // const controlPlaneBootstrap = new talos.machine.Bootstrap(`talos-boostrap-${suffix}`, {
    //     node: item.ip,
    //     clientConfiguration: talosSecrets.clientConfiguration
    // }, { dependsOn: [...boostrapDependsOn, controlPlaneConfigurationApply] });
    // boostrapDependsOn.push(controlPlaneBootstrap);
})

const getKubeconfig = (): Promise<string> => new Promise(resolve => {
    talosConfiguration.clientConfiguration.apply(async c => {
        const kubeconfigResult = await talos.cluster.getKubeconfig({
            clientConfiguration: c,
            node: clusterEndpoint,
        });
        return resolve(kubeconfigResult.kubeconfigRaw);
    })
})

// https://archive.pulumi.com/t/12112464/hi-all-any-solution-for-argument-of-type-output-lt-string-gt#064d59d8-7726-466d-8363-24176958b557
export const kubeconfig = pulumi.secret(await getKubeconfig());

const fluxCdDependsOn = [...boostrapDependsOn];

const key = new PrivateKey("flux-cd-deploy-key", {
    algorithm: "ECDSA",
    ecdsaCurve: "P256",
}, { dependsOn: fluxCdDependsOn });

const githubOwner = "sylvainmetayer";
const repoName = "homelab";
const branch = "main";
const knownHosts =
    "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=";

const deployKey = new RepositoryDeployKey("fluxcd-key", {
    title: "pulumi-fluxcd",
    repository: repoName,
    key: key.publicKeyOpenssh,
    readOnly: true,
});

const targetPath = 'clusters/homelab/flux/flux-system';

// TODO pass kubeconfig as parameter in provider configuration.
if (existsSync(`${homedir()}/.kube/config`)) {

    const k8sProvider = new k8s.Provider('k8s_provider', { kubeconfig: await getKubeconfig() });
    const fluxProvider = new flux.Provider("flux_provider", {
        kubernetes: {
            configPath: "~/.kube/config",
        },
        git: {
            url: `ssh://git@github.com/${githubOwner}/${repoName}.git`,
            branch,
            ssh: {
                username: "git",
                privateKey: key.privateKeyPem,
            },
        },
    });

    const fluxInstall = await flux.getFluxInstall({
        // TODO renovate upgrade comment
        version: 'v2.5.1',
        targetPath: targetPath,
    });

    const fluxSync = await flux.getFluxSync({
        targetPath: 'clusters/homelab/flux/flux-system',
        secret: 'flux-ssh-key',
        url: `ssh://git@github.com/${githubOwner}/${repoName}.git`,
        branch: branch,
    });

    // Create kubernetes resource from generated manifests
    const install = new k8s.yaml.ConfigGroup("flux-install", {
        yaml: fluxInstall.content,
    });

    const sync = new k8s.yaml.ConfigGroup("flux-sync", {
        yaml: fluxSync.content,
    }, {dependsOn: install});

    //writeFileSync("flux_sync.yaml", fluxSync.content);
    //writeFileSync("flux_install.yaml", fluxInstall.content);

    const fluxSshKey = new k8s.core.v1.Secret(
        "flux",
        {
            metadata: {
                name: fluxSync.secret,
                namespace: fluxSync.namespace,
            },
            stringData: {
                identity: key.privateKeyPem,
                "identity.pub": key.publicKeyPem,
                known_hosts: knownHosts,
            },
        },
        { dependsOn: [install] }
    );
}


export const talosConfig = talosConfiguration.talosConfig;

// https://www.pulumi.com/registry/packages/talos/api-docs/cluster/getkubeconfig/
// https://www.pulumi.com/registry/packages/flux/api-docs/fluxbootstrapgit/
// https://kubernetes.github.io/ingress-nginx/examples/auth/oauth-external-auth/
// https://github.com/siderolabs/talos/discussions/6970