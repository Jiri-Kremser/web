---
title: "Prototyping a web app that can talk to Kubernetes API"
date: 2020-05-25
tags: ["kubernetes", "development", "frontend", "API", "JavaScript", "express.js"]
disqus_identifier: "web-app-k8s"
disqus_title: "Prototyping a web app that can talk to Kubernetes API"
draft: true
---

# Motivation
todo: https://learnk8s.io/real-time-dashboard

With the advent of various types of [operators](https://coreos.com/operators/) on top of Kubernetes platform, it might be useful to provide users with a fancy dashboard. However, dashboards these days are often written in JavaScript and libraries/frameworks like React.js, Vue.js or Angular. Kubernetes API on the other hand is a bunch of REST endpoints. So it all may look pretty simple, just call those endpoints from the app written in JavaScript, right? Unfortunatelly, it's not that simple, because of the AuthN and AuthZ that is by default turned on in the Kubernetes REST endpoints and giving the bearer token to the client-side JavaScript app might be a security risk.

Let's dive into the problem and let's code some very simple web application in the following two blog posts.

## Design
Here is the idea. We know that client-side JavaScript app will by definition run on the client side, but at the same time we need to be able to access the K8s api using the token. 
So let's split the webapp into two pieces:
 - server-side: the rest endpoints with only those APIs that we will be calling from the client-side
 - client-side: application in React.js

In other words the server-side rest endpoints will be transforming the incoming request to the request for the Kubernetes API. Because of the fact it will be deployed on a pod in k8s, it will have an access to the secrets w/ the CA certificate and baerer token representing the service account. So that RBAC can be controlled by Kubernetes itself. Our goal will be to list all the deployments in the cluster that have given label on them. This is a common pattern when working with operators, because it's a good practice to label the resources it creates.

{{< figure src="/k8s-webapp-1/k8s-web-app.svg" >}}

## Part 1 - the server-side

We are lazy so we would like to write as little of code as possible. Let's scaffold an example Express.js application using [Yeoman generator](https://github.com/cdimascio/generator-express-no-stress). It is not super up-to-date, but it generates also swagger specs (OpenAPI 3) and contains also swagger ui out of the box. It also comes with the preinstalled JavaScript linter.

Install the generator:
```bash
npm install -g yo generator-express-no-stress
```

Scaffold the app:
```bash
yo express-no-stress rest-api
```

Check what has been generated:
```
tree rest-api/server/
rest-api/server/
├── api
│   ├── controllers
│   │   └── examples
│   │       ├── controller.js
│   │       └── router.js
│   ├── middlewares
│   │   └── error.handler.js
│   └── services
│       ├── examples.db.service.js
│       └── examples.service.js
├── common
│   ├── api.yml
│   ├── env.js
│   ├── logger.js
│   ├── oas.js
│   └── server.js
├── index.js
└── routes.js
```
