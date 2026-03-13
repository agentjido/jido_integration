defmodule Jido.Integration.Test.ScopedAdapter do
  @moduledoc false
  @behaviour Jido.Integration.Adapter

  alias Jido.Integration.{Error, Manifest}

  @impl true
  def id, do: "scoped_adapter"

  @impl true
  def manifest do
    Manifest.new!(%{
      "id" => "scoped_adapter",
      "display_name" => "Scoped Adapter",
      "vendor" => "Jido Test",
      "domain" => "saas",
      "version" => "0.1.0",
      "quality_tier" => "bronze",
      "telemetry_namespace" => "jido.integration.scoped_adapter",
      "auth" => [
        %{
          "id" => "oauth2",
          "type" => "oauth2",
          "display_name" => "Scoped OAuth2",
          "secret_refs" => ["client_id", "client_secret"],
          "scopes" => ["repo"],
          "token_semantics" => "bearer",
          "tenant_binding" => "tenant_only",
          "oauth" => %{
            "grant_type" => "authorization_code",
            "auth_url" => "https://example.com/oauth/authorize",
            "token_url" => "https://example.com/oauth/token"
          }
        }
      ],
      "operations" => [
        %{
          "id" => "scoped.read",
          "summary" => "Read a scoped resource",
          "input_schema" => %{
            "type" => "object",
            "properties" => %{
              "resource_id" => %{"type" => "string"}
            },
            "required" => ["resource_id"],
            "additionalProperties" => false
          },
          "output_schema" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"}
            },
            "required" => ["id"]
          },
          "errors" => [
            %{
              "code" => "scoped.invalid_request",
              "class" => "invalid_request",
              "retryability" => "terminal"
            },
            %{
              "code" => "scoped.auth_failed",
              "class" => "auth_failed",
              "retryability" => "terminal"
            }
          ],
          "required_scopes" => ["repo"]
        }
      ]
    })
  end

  @impl true
  def validate_config(config), do: {:ok, config}

  @impl true
  def health(_opts), do: {:ok, %{status: :healthy, details: %{}}}

  @impl true
  def run("scoped.read", %{"resource_id" => resource_id}, _opts) do
    Process.put(:scoped_adapter_ran, true)
    {:ok, %{"id" => resource_id}}
  end

  def run(op, _args, _opts) do
    {:error, Error.new(:unsupported, "Unknown operation: #{op}")}
  end
end

defmodule Jido.Integration.Test.CrashyAdapter do
  @moduledoc false
  @behaviour Jido.Integration.Adapter

  alias Jido.Integration.Manifest

  @impl true
  def id, do: "crashy_adapter"

  @impl true
  def manifest do
    Manifest.new!(%{
      "id" => "crashy_adapter",
      "display_name" => "Crashy Adapter",
      "vendor" => "Jido Test",
      "domain" => "protocol",
      "version" => "0.1.0",
      "quality_tier" => "bronze",
      "telemetry_namespace" => "jido.integration.crashy_adapter",
      "auth" => [
        %{
          "id" => "none",
          "type" => "none",
          "display_name" => "No Auth"
        }
      ],
      "operations" => [
        %{
          "id" => "crashy.run",
          "summary" => "Raises during execution",
          "input_schema" => %{"type" => "object"},
          "output_schema" => %{
            "type" => "object",
            "properties" => %{"ok" => %{"type" => "boolean"}},
            "required" => ["ok"]
          },
          "errors" => [
            %{
              "code" => "crashy.internal",
              "class" => "internal",
              "retryability" => "fatal"
            }
          ]
        }
      ]
    })
  end

  @impl true
  def validate_config(config), do: {:ok, config}

  @impl true
  def health(_opts), do: {:ok, %{status: :healthy, details: %{}}}

  @impl true
  def run("crashy.run", _args, _opts) do
    raise "boom"
  end
end

defmodule Jido.Integration.Test.BadResultAdapter do
  @moduledoc false
  @behaviour Jido.Integration.Adapter

  alias Jido.Integration.{Error, Manifest}

  @impl true
  def id, do: "bad_result_adapter"

  @impl true
  def manifest do
    Manifest.new!(%{
      "id" => "bad_result_adapter",
      "display_name" => "Bad Result Adapter",
      "vendor" => "Jido Test",
      "domain" => "protocol",
      "version" => "0.1.0",
      "quality_tier" => "bronze",
      "telemetry_namespace" => "jido.integration.bad_result_adapter",
      "auth" => [
        %{
          "id" => "none",
          "type" => "none",
          "display_name" => "No Auth"
        }
      ],
      "operations" => [
        %{
          "id" => "bad_result.run",
          "summary" => "Returns a payload that violates the output schema",
          "input_schema" => %{"type" => "object"},
          "output_schema" => %{
            "type" => "object",
            "properties" => %{"ok" => %{"type" => "boolean"}},
            "required" => ["ok"],
            "additionalProperties" => false
          },
          "errors" => [
            %{
              "code" => "bad_result.internal",
              "class" => "internal",
              "retryability" => "fatal"
            }
          ]
        }
      ]
    })
  end

  @impl true
  def validate_config(config), do: {:ok, config}

  @impl true
  def health(_opts), do: {:ok, %{status: :healthy, details: %{}}}

  @impl true
  def run("bad_result.run", _args, _opts), do: {:ok, %{"unexpected" => true}}

  def run(op, _args, _opts) do
    {:error, Error.new(:unsupported, "Unknown operation: #{op}")}
  end
end

defmodule Jido.Integration.Test.ConflictingAdapter do
  @moduledoc false
  @behaviour Jido.Integration.Adapter

  alias Jido.Integration.{Error, Manifest}

  @impl true
  def id, do: "test_adapter"

  @impl true
  def manifest do
    Manifest.new!(%{
      "id" => "test_adapter",
      "display_name" => "Conflicting Test Adapter",
      "vendor" => "Jido Test",
      "domain" => "protocol",
      "version" => "0.1.0",
      "quality_tier" => "bronze",
      "telemetry_namespace" => "jido.integration.test_adapter",
      "auth" => [
        %{
          "id" => "none",
          "type" => "none",
          "display_name" => "No Auth"
        }
      ],
      "operations" => []
    })
  end

  @impl true
  def validate_config(config), do: {:ok, config}

  @impl true
  def health(_opts), do: {:ok, %{status: :healthy, details: %{}}}

  @impl true
  def run(_op, _args, _opts) do
    {:error, Error.new(:unsupported, "No operations implemented")}
  end
end

defmodule Jido.Integration.Test.InvalidErrorAdapter do
  @moduledoc false
  @behaviour Jido.Integration.Adapter

  alias Jido.Integration.{Error, Manifest}

  @impl true
  def id, do: "invalid_error_adapter"

  @impl true
  def manifest do
    Manifest.new!(%{
      "id" => "invalid_error_adapter",
      "display_name" => "Invalid Error Adapter",
      "vendor" => "Jido Test",
      "domain" => "protocol",
      "version" => "0.1.0",
      "quality_tier" => "bronze",
      "telemetry_namespace" => "jido.integration.invalid_error_adapter",
      "auth" => [
        %{
          "id" => "none",
          "type" => "none",
          "display_name" => "No Auth"
        }
      ],
      "operations" => [
        %{
          "id" => "invalid_error.run",
          "summary" => "Declares an invalid error class",
          "input_schema" => %{"type" => "object"},
          "output_schema" => %{"type" => "object"},
          "errors" => [
            %{
              "code" => "invalid_error.not_real",
              "class" => "not_real",
              "retryability" => "terminal"
            }
          ]
        }
      ]
    })
  end

  @impl true
  def validate_config(config), do: {:ok, config}

  @impl true
  def health(_opts), do: {:ok, %{status: :healthy, details: %{}}}

  @impl true
  def run("invalid_error.run", _args, _opts), do: {:ok, %{}}

  def run(op, _args, _opts) do
    {:error, Error.new(:unsupported, "Unknown operation: #{op}")}
  end
end
