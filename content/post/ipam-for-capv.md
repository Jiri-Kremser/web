---
title: "IP Address Management for Cluster API & onprem"
date: 2023-08-08
tags: ["kubernetes", "development", "capi", "ipam", "capv"]
disqus_identifier: "web-app-k8s"
disqus_title: "IP Address Management for Cluster API & onprem"
draft: false
---

# Motivation

Cluster API (CAPI) provides uniform workflow for deploying and operating Kubernetes clusters. It aims to abstract its user from the infrastructure level.
The infrastructure in the form of VMs can be provided by a cloud provider like AWS or Azure. However these platform often supports also managed kubernetes experience (EKS, AKS), where a lot of features like load balancing, managed control planes are just there.

In this blog post we will be looking into a situation where basically no advanced features are provided and all we have is a virtualization platform like `vSphere`. 
In this case we are on our own and we need to manage the load balancing and IP management on our own. All the article is tackeling only the IPv4, but it could be generalized also to IPv6 stack.

## Problem Landscape

For the Cluster API to be a useful tool, it needs to be installed in certain flavor denoting what infrastructures it can talk to. This is captured in infrastructure provider component. We will be using CAPV (Cluster API provider for vSphere). CAPV itself can already deploy a brand new Kubernetes cluster and also provide day-2 operations for it. This is done by dedicating one Kubernetes cluster as a management cluster (MC) where all these CAPI related controllers run. Then when a set of resources (where the main/root one is the `Cluster` CR) is created, they start to do its thing and provision the (workload) cluster (WC).

Each infrastructure provider is different and provides different level of comfort. For instance the `vSphere` can create machines with given IPs or use DHCP. However, their CPI (cloud provider interface) component doesn't support the load balancer for services so we need to use something else.

Also when creating a new cluster, at least the IP for control plane needs to be known in advance (capv). The reason for this is that capv uses kube-vip by default to enable the control planes to run in HA mode. Kubevip then selects one of the control-planes as the primary one and creates a virtual IP for it. The failover is then solved by leader election mechanism by using kubernetes [primitives](https://kubernetes.io/docs/reference/kubernetes-api/cluster-resources/lease-v1/). When we create a new WC, we need a new free IP for it.

That's the problem that can be solved by IP address management (IPAM).

### Architecture

For better visualisation of the problem, check the following diagram of our overall platform.

{{< figure src="/ipam-for-capv/platform.png" >}}

## Part 1 - Service Load Balancer

As we mentioned before, we don't have the full support for cloud provider here so if we create a service with type `LoadBalancer`, it will stay in the pending state forever. Luckily, there are multiple solutions out there.

We have considered using `MetalLB` and `Cilium` but both of them required to configure BGP properly (ASN numbers) so for the sake of simplicity we choose to use simple [`kube-vip`](https://kube-vip.io/) project with ARP advertisment. That means that we currently deploy kube-vip in two different flavors:

a) used for control-plane HA (static pod on each control plane node)
b) used as a service LB (deployed as `DaemonSet`)

Part of the LB solution is also a kubevip's [controller controller manager](https://github.com/kube-vip/kube-vip-cloud-provider). This component is also specific to on-prem and its goal is to assign an new free IP from given a CIDR. It watches to all changes to a `Service` resource of type `LoadBalancer` and if the IP is not set, it assign a new one. Then it is up to kube-vip LB to create a new virtual interface on the given node and advertise this new IP in the network usith the layer 2 ARP protocol.

The range of IPs for service LB is defined as a configmap:

```bash
λ k get cm kubevip -n kube-system -o jsonpath={.data} | jq
{
  "cidr-global": "10.10.222.231/32"
}
```

It also supports a per-namespace ranges, but we don't use it.


## Part 2 - IPAM

This is a orthogonal problem to the previous one, but it also includes IPAM. When creating a new cluster using Cluster API, one has to create a whole bunch of kubernetes resources. There are tutorials, docs and presentations about CAPI, so we are not going to describe it in the detail, but rather from a high perspective. These resources form a tree and are cross-linked by references in their `.spec`s. CAPI consist of four controllers and each of them react on various CRs from that tree of yamls. Luckily the overall reconcilliation of a new cluster can be paused by setting such flag on the top-lvl CR - Cluster. We will use that later on.

What we are going to need is a controller/operator that keeps tracks of used IP adresses and can allocate new ones, ideally in kubernetes native way. CAPI itself
introduces following CRDs:
- `IPAddress`
- `IPAddressClaim`

And the idea is that one can create an `IPAddressClaim` CR with a reference to a "pool" and someone should create an new `IPAddress` with the same name as the claim satisfying the IP adress range definition from the pool. One implementor of this contract is the [cluster-api-ipam-provider-in-cluster](https://github.com/kubernetes-sigs/cluster-api-ipam-provider-in-cluster) that we ended up using.

Example:

```bash
λ k get globalinclusterippools.ipam.cluster.x-k8s.io
NAME        ADDRESSES                         TOTAL   FREE   USED
wc-cp-ips   ["10.10.222.232-10.10.222.238"]   7       6      1
```

```yaml
λ cat <<IP | kubectl apply -f -
apiVersion: ipam.cluster.x-k8s.io/v1alpha1
kind: IPAddressClaim
metadata:
  name: give-me-an-ip
spec:
  poolRef:
    apiGroup: ipam.cluster.x-k8s.io
    kind: GlobalInClusterIPPool
    name: wc-cp-ips
IP
ipaddressclaim.ipam.cluster.x-k8s.io/give-me-an-ip created
```

```bash
λ k get ipaddress give-me-an-ip
NAME            ADDRESS         POOL NAME   POOL KIND
give-me-an-ip   10.10.222.233   wc-cp-ips   GlobalInClusterIPPool
```

```bash
λ k get globalinclusterippools.ipam.cluster.x-k8s.io
NAME        ADDRESSES                         TOTAL   FREE   USED
wc-cp-ips   ["10.10.222.232-10.10.222.238"]   7       5      2
```

CAPV itself has a support for IPAM already included, but this is limited to creating the VMs and assigning them IPs.

```bash
k explain vspheremachine.spec.network.devices.addressesFromPools
...
DESCRIPTION:
    AddressesFromPools is a list of IPAddressPools that should be assigned to
    IPAddressClaims. The machine's cloud-init metadata will be populated with
    IPAddresses fulfilled by an IPAM provider.
    TypedLocalObjectReference contains enough information to let you locate the
    typed referenced object inside the same namespace.
```

It means that each VM created from given template will have an IP address managed using the `IPAddress` and `IPAddressClaim`. That's both over-kill and also not sufficient. It's overkill, because we don't need to take those non-important VMs (like worker nodes, or other control planes (CP) when running in HA) those precious IPs, we care only about one virtual api for all control planes running in HA mode as described in kube-vip (control plane HA use-case).

Also it is not sufficient, because it can't propagate that IP into other resources in that tree of objects where the information is needed:
- `.spec.controlPlaneEndpoint.host` in `VsphereCluster` CR
- static pod definition for kubevip in `KubeadmControlPlane` (file with static pod is mounted to each CP node)
- `.spec.kubeadmConfigSpec.clusterConfiguration.apiServer.certSANs` same `KubeadmControlPlane` CR as the previous one

todo

## Part 3 - Kyverno policy
todo

## Conclusion
todo

