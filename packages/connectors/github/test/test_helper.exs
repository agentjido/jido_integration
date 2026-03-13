live_enabled? =
  System.get_env("JIDO_INTEGRATION_GITHUB_LIVE") in ["1", "true", "TRUE", "yes", "YES"]

live_write_enabled? =
  System.get_env("JIDO_INTEGRATION_GITHUB_LIVE_WRITE") in ["1", "true", "TRUE", "yes", "YES"]

exclude =
  [:skip]
  |> then(fn tags -> if live_enabled?, do: tags, else: [:live | tags] end)
  |> then(fn tags -> if live_write_enabled?, do: tags, else: [:live_write | tags] end)

ExUnit.start(exclude: exclude)
