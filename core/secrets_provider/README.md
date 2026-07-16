# Jido Integration Secrets Provider

This package owns the dependency-light secrets provider contract used by
generic credential ingress. It keeps public requests and receipts on lease
refs, provider refs, and audit refs while allowing raw credential material only
inside a brokered adapter call scope.

The local command adapter is `Jido.Integration.Secrets.EnvProvider`. Production
managed-account calls use
`Jido.Integration.Secrets.ManagedCredentialMaterializer` with an explicitly
configured provider such as `Jido.Integration.Secrets.VaultKVProvider`; no
provider address or token is discovered from ambient process environment.
Receipts from this package must never include raw secret material.
