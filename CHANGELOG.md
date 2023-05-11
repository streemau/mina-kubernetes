## 3.0.1

*Fixes*

- Use `File.exist?` instead of `File.exists?` which was removed from Ruby 3.2

## 3.0.0

*Breaking change*

- Depend on [Krane 3.0.0](https://github.com/Shopify/krane/blob/master/CHANGELOG.md#300)

## 2.7.1

*Fixes*

- Use `--dry-run=client` instead of deprecated `--dry-run` with kubectl to create/update namespace

## 2.7.0

*Enhancements*

- `kubernetes:command` allows to choose pod name
- `kubernetes:command` offers to kill & start fresh pod or start other pod with different name if pod already exists

## 2.6.0

*Fixes*

- Update krane gem to ~> 2.1 for compatibility with k8s >= 1.17

## 2.5.0

*Enhancements*

- `kubernetes:command` starts pod with identifiable name and allows session reconnection
- `kubernetes:command` accepts a `kubectl_pod_overrides` option

## 2.4.1

*Fixes*

- Security: update rake dependency

## 2.4.0

*Enhancements*

- Use `secrets.ejson` if present

## 2.3.0

*Enhancements*

- Allow using a proxy to connect to a Kubernetes cluster

## 2.2.4

*Fixes*

- run custom command within given namespace instead of `default` 

## 2.2.1 to 2.2.3

*Fixes*

- handle nil/undefined options passed to `krane`

## 2.2.0

*Enhancements*

- Using `krane` 1.0.0 (previously `kubernetes-deploy`)
- Allow passing of options to `krane`

## 2.1.0

Yanked release.

## 2.0.0

*Breaking*

- Using `namespace` config variable instead of `app_name`
- Using `kubernetes_context` config variable linking directly to a context set in $KUBE_CONFIG instead of creating a new context from separate `kubernetes_cluster` and `kubernetes_user` config variables

*Fixes*

- Not overriding $KUBE_CONFIG environment variable anymore
