# Usage Rules

- treat `Jido.BoundaryBridge` as a stateless translation seam, not as durable authority
- pass already-normalized runtime and policy intent into the bridge
- use deterministic `boundary_session_id` values for retry-safe allocate and reopen calls
- treat `policy_intent_echo` as lossy execution evidence, not as authoritative governance input
- keep durable session carriage explicit through named route, attach-grant,
  replay, approval, callback, and identity fields
- ignore unknown extension namespaces unless your consumer explicitly supports them
