## 2.0.0

*Breaking*

- Using `namespace` config variable instead of `app_name`
- Using `kubernetes_context` config variable linking directly to a context set in $KUBE_CONFIG instead of creating a new context from separate `kubernetes_cluster` and `kubernetes_user` config variables

*Fixes*

- Not overriding $KUBE_CONFIG environment variable anymore