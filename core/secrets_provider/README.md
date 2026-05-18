# Jido Integration Secrets Provider

This package owns the dependency-light secrets provider contract used by
generic credential ingress. It keeps public requests and receipts on lease
refs, provider refs, and audit refs while allowing raw credential material only
inside a brokered adapter call scope.

The local command adapter is `Jido.Integration.Secrets.EnvProvider`. Production
hosts provide a keyring or KMS-style adapter with key IDs, rotation posture,
revocation behavior, and explicit fail-closed errors. Receipts from this
package must never include raw secret material.
