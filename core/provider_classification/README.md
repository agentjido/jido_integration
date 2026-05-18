# Jido Integration Provider Classification

This package owns the dependency-light provider and adapter classification
vocabulary shared by Jido Integration, Citadel, OuterBrain, StackLab, and other
generic platform packages.

It contains no connector runtime dependencies. Packages that only need to
classify provider vocabulary should depend on this package instead of the full
`jido_integration_contracts` package.
