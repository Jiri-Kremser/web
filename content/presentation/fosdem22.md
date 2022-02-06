---
title: "A cloud native Kubernetes Global Balancer @ FOSDEM 22"
description: "k8gb is DNS based global service load balancer that can interconnect multiple Kubernetes clusters into one resilient system. Join this talk to learn how it can handle a failover scenario when pods in one cluster go down and second cluster in different location saves the situation.

k8gb is an open-source Kubernetes operator that is deployed in each participating cluster. It is comprised of CoreDNS, ExternalDNS and the k8gb controller itself. Using ExternalDNS it can create a zone delegation on a common cloud DNS server like Route53 or Infoblox so that the embedded CoreDNS servers work as an authoritative DNS. K8gb controller makes sure these CoreDNS servers are updated accordingly based on the readiness probes of the application.

In this sense this solution is unique, because it is using Kubernetes native tools with customisable probes and battle tested DNS protocol instead of HTTP pings or other similar approaches where single point of failure might be a problem. In k8gb architecture all k8s clusters are equal and there is no SPoF except the common edge DNS server."
link: "https://fosdem.org/2022/schedule/event/container_k8gb_balancer/"
tags: ["k8gb", "FOSDEM", "kubernetes-operator"]
weight: 6
draft: false
---