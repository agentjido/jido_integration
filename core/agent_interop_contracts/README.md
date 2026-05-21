# Jido Integration Agent Interop Contracts

This package owns the generic contracts for external agent interop. It does not
implement any specific external-agent protocol, transport adapter, generated
module set, or live connector.

The public surface is descriptor, capability, invocation, policy reference, and
runtime receipt data. Concrete protocol facts remain data in descriptor refs and
transport packages.

