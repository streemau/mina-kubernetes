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
