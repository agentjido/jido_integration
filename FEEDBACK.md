# Feedback: Growing Jido Integration V2 into a Jido-Native Integration Catalog

Date: 2026-03-17
Status: draft feedback memo

## Why This Memo Exists

`jido_integration` already proves a strong V2 baseline: thin connectors,
explicit package boundaries, durable auth and control-plane truth, conformance,
and clear separation between connector logic and host-level proof surfaces.

The next gap is not "make the connectors fatter." The next gap is to evolve the
repo from an invoke-centric integration platform into a Jido-native integration
catalog that can support many integrations and expose them cleanly to the rest
of the ecosystem.

The product-shape benchmark here is the kind of action-plus-trigger directory
you see in tools like [Lindy](https://www.lindy.ai/integrations),
[Lindy Notion](https://www.lindy.ai/integrations/notion), and
[Zapier Apps](https://zapier.com/apps). The Jido-native version of that should
not be "hundreds of handwritten wrapper modules." It should be thin provider
connectors plus a richer contract that can project into Jido Actions, Sensors,
Plugins, docs, and catalog surfaces.

## What The Current Repo Already Gets Right

The current V2 repo has several important design choices that should be
preserved:

- thin provider connectors backed by provider SDKs instead of duplicate fake
  provider layers
- explicit package boundaries and path dependencies
- a strong public control plane in `Jido.Integration.V2`
- durable install, connection, lease, run, event, artifact, and trigger truth
- explicit policy posture at the capability boundary
- connector conformance as a first-class repo surface
- clear separation between connector contracts and app-owned webhook or async
  composition

The Notion connector is a good example of the current strengths. It keeps the
provider boundary thin, keeps OAuth control in install/auth flows instead of
widening the invoke surface, and relies on Jido for auth truth, leases, policy,
and reviewability.

None of the feedback below is an argument to undo that work. The point is to
add the next layer above it.

## The Core Gap

Today the public integration story is invoke-centric and connector-centric.
That is enough to prove runtime classes and durable control-plane semantics, but
it is not yet enough to support a large integration catalog that feels native to
the Jido ecosystem.

There are four main gaps.

### 1. The public connector contract is too thin for projection

`Capability` is mostly runtime metadata plus opaque `metadata`. That works for
invocation, but it is not rich enough to drive:

- tool generation for `jido_ai`
- trigger generation for `Jido.Sensor`
- plugin generation for `Jido.Plugin`
- integration-directory docs and UX
- schema-complete catalogs across many providers

The missing pieces are first-class operation schemas, trigger schemas, auth
metadata, and catalog metadata.

### 2. Trigger support stops below the Jido Sensor layer

The repo already has durable trigger admission through `Ingress`, route
management through `WebhookRouter`, and replay/recovery through
`DispatchRuntime`. That is good platform infrastructure.

But it is still infrastructure. It is not yet the surface a Jido user wants.

An agent author should not have to think in terms of:

- app-owned trigger handlers
- webhook route registration
- dispatch runtime handlers
- ingress normalization

They should be able to think in terms of:

- "subscribe this agent to a Notion trigger"
- "receive a stable Jido signal"
- "route that signal through plugin logic"

Right now the repo proves trigger durability, but it does not project those
triggers into `Jido.Sensor` surfaces.

### 3. The repo is not yet Jido-native at the consumption boundary

The current repo does not expose first-class:

- `Jido.Action` surfaces for connector capabilities
- `Jido.Sensor` surfaces for connector triggers
- `Jido.Plugin` bundles for agent consumption
- `jido_ai`-friendly integration packaging

There is also some implementation drift here: the direct runtime docs talk
about `Jido.Action`, but the shipped direct connectors execute through plain
`run/2` handler modules. That means the repo has some Jido-shaped language, but
not yet a productized Jido-native boundary.

### 4. The generator and conformance story stop too early

`mix jido.integration.new` is good for scaffolding a thin connector package.
The conformance surface is good for validating the current runtime-first model.

But if the repo wants to scale to many integrations, the default authoring and
review path also needs to cover:

- schema completeness
- trigger completeness
- catalog metadata completeness
- generated Jido surface correctness
- plugin wiring and agent-facing usability

Without that, every new integration will still require too much bespoke
decision-making.

## Concrete User Story: A Notion-Powered Jido AI Agent

The simplest way to reason about the gap is through a concrete user story.

Imagine someone using `jido_ai` to build an agent that should:

- react to changes in Notion
- inspect pages or comments
- write back to Notion

What that person should be able to do is something conceptually like this:

1. install or bind a Notion connection once
2. mount a Notion plugin on their `Jido.AI.Agent`
3. expose a selected set of Notion tools to the model
4. subscribe to one or more Notion triggers via sensors
5. handle emitted signals through agent or plugin routing
6. call back into Notion through generated tools without manually wiring
   `invoke/3`, leases, or policy opts every time

That is not the current experience.

The current experience is closer to:

- register the connector
- manage install and connection state directly through `Jido.Integration.V2`
- obtain or pass credential references
- call `invoke/3` yourself
- build app-owned trigger handling around ingress and dispatch

That is a strong platform API. It is not yet an agent-authoring API.

For a repo that wants to support many many integrations, the missing bridge is
not more hand-coded provider logic. The missing bridge is a projection layer
that turns the integration contracts into Jido-native surfaces.

## End-State Architecture

The end state should keep the existing V2 architecture as the execution and
durability backbone while adding a richer projection layer above it.

### Keep the current backbone

The following parts should remain foundational:

- `Jido.Integration.V2` as the stable public facade
- auth, leases, and policy in the current core packages
- durable run, event, artifact, target, and trigger truth
- thin connector packages as isolated deliverables
- app-level proof surfaces for host composition

### Evolve the contract

The connector contract needs to become rich enough to drive multiple consumer
surfaces without turning each connector into a large bespoke codebase.

At minimum, the public model should add first-class concepts for:

- operation specs
- trigger specs
- auth metadata
- catalog metadata

Each operation spec should carry stable identifiers, descriptions, permission
requirements, schemas, and the runtime mapping needed to execute it through the
existing control plane.

Each trigger spec should carry stable identifiers, descriptions, trigger config
schema, emitted signal schema, delivery mode, and checkpoint or dedupe posture.

Use `Zoi` as the canonical schema format inside the repo, then derive JSON
Schema as needed for docs, catalog rendering, or LLM tool exposure.

### Add a shared projection layer

The scalable unit should be:

- one thin connector manifest
- one set of schemas and metadata
- many projected surfaces generated from that source of truth

That projection layer should generate connector-local:

- `Jido.Action` modules for invokable operations
- `Jido.Sensor` modules for triggers
- `Jido.Plugin` bundles for agent consumption

The generation should be shared and template-driven, not handwritten per
operation.

Generated actions should call `Jido.Integration.V2.invoke/3` under the hood and
hide low-level invoke plumbing from agent authors. Generated sensors should come
from trigger specs, with poll-backed sensors first and hosted-webhook relay
sensors later. Generated plugins should bundle actions, subscriptions, config
schema, and routing defaults.

### Keep workflows out of connectors

Even after this evolution, connectors should stay thin. They should not become
the place where application workflows live.

The split should be:

- connectors own provider mapping and metadata
- the platform owns execution and durability
- the projection layer owns Jido-native surfaces
- apps and agents own workflows and composition

That keeps the repo scalable.

## Proposed Roadmap

### Phase 1: Richer integration contracts

Add first-class operation specs, trigger specs, auth metadata, and catalog
metadata to the public contract while keeping the existing capability model
compatible during migration.

This is the minimum change needed to stop treating connector metadata as opaque
runtime-only state.

### Phase 2: Generated Action and Plugin surfaces

Add a shared projection package that can generate connector-local
`Jido.Action` modules and `Jido.Plugin` bundles from the manifest.

This should be the first real Jido-native consumption surface for connectors.
It gives `jido_ai` users something useful immediately without forcing every
trigger path to be solved first.

### Phase 3: Poll-backed Sensor generation

Add trigger specs and generate poll-backed `Jido.Sensor` modules from them.

This is the simplest and cleanest way to make connector triggers feel native to
Jido, because it maps cleanly onto the current Sensor model and can reuse the
existing checkpoint truth already present in the platform.

### Phase 4: Hosted webhook relay into the same Sensor model

Do not push hosted webhooks down into connector packages.

Instead, bridge the existing `WebhookRouter` + `Ingress` + `DispatchRuntime`
stack into the same sensor-facing model so webhook-backed triggers and
poll-backed triggers converge on a consistent Jido signal surface.

### Phase 5: Upgrade scaffolding and conformance

Teach the generator and conformance suite about the richer model.

New connectors should start with:

- projection-ready contracts
- operation schemas
- trigger skeletons
- generated Jido surfaces
- validation for catalog readiness

This is the difference between "a repo that can host many integrations" and "a
repo that can grow many integrations reliably."

## Notion As The First Full Reference Slice

Notion should become the first full reference slice for this next stage.

That means:

- keep the existing thin Notion connector approach
- project its action surface into generated `Jido.Action` modules
- add at least one useful trigger surface for sensors
- expose a Notion plugin suitable for `jido_ai`

The point is not that Notion is special. The point is that Notion is a concrete
and believable integration for proving the full shape:

- install and auth
- trigger consumption
- tool invocation
- agent-facing plugin ergonomics
- durable reviewability through the existing control plane

## Recommended Boundaries

This should start in `jido_integration`.

It is reasonable to expect downstream follow-on work in `jido` or `jido_ai` if
the current Action, Sensor, or Plugin APIs prove insufficient. But the first
step should be to make `jido_integration` rich enough to project into the
current ecosystem surfaces before assuming those libraries need to change.

It is also important not to widen the connectors in the wrong way.

The repo should not solve this by:

- hand-writing one action wrapper per provider method
- putting workflows into connector packages
- moving hosted webhook logic back into connectors
- weakening the current boundary between auth control and normal runtime invoke

The right move is richer contracts plus generated projections.

## Success Criteria

From an agent author's perspective, success looks like this:

- I can mount an integration plugin on a `Jido.AI.Agent`
- I can expose selected actions as tools
- I can subscribe to selected triggers as sensors
- I can react to signals and call back into the provider
- I do not have to manually wire leases, invoke opts, ingress handlers, or
  dispatch handlers just to use a connector

From the platform's perspective, success looks like this:

- new integrations are added by extending a rich connector manifest, not by
  growing large bespoke code surfaces
- conformance can validate not just runtime behavior, but also catalog and
  projection completeness
- the same integration contract can feed execution, documentation, plugins,
  tools, and triggers
- the repo can grow toward a true integration catalog without giving up the V2
  strengths it already has
