%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "core/*/lib/",
          "connectors/*/lib/",
          "apps/*/lib/"
        ],
        excluded: [
          "_build/",
          "deps/",
          "dist/",
          "packaging/"
        ]
      },
      checks: [
        {Weld.Credo.Check.NoRuntimeOsEnv, []}
      ]
    }
  ]
}
