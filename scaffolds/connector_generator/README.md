# Jido Integration Connector Generator

Internal generator package for in-tree and external companion connector
skeletons.

Generated external companion output is explicit app-config input only. It does
not grant platform admission and does not create package auto-discovery.

## Verification

```bash
mix test
mix compile --warnings-as-errors
```
