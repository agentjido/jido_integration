defmodule Jido.Integration.Operation.Descriptor do
  @moduledoc """
  Operation descriptor — declares a single operation in a connector manifest.

  Each operation has an ID, schemas for input/output, error declarations,
  idempotency requirements, timeout, rate limit, and required scopes.
  """

  alias Jido.Integration.Error

  @valid_idempotency ~w(required optional none)

  @type t :: %__MODULE__{
          id: String.t(),
          summary: String.t(),
          input_schema: map(),
          output_schema: map(),
          errors: [map()],
          idempotency: String.t(),
          timeout_ms: non_neg_integer(),
          rate_limit: String.t() | map(),
          required_scopes: [String.t()]
        }

  @enforce_keys [:id, :summary]
  defstruct [
    :id,
    :summary,
    input_schema: %{"type" => "object"},
    output_schema: %{"type" => "object"},
    errors: [],
    idempotency: "optional",
    timeout_ms: 30_000,
    rate_limit: "gateway_default",
    required_scopes: []
  ]

  @doc """
  Create a new operation descriptor from a map.
  """
  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         :ok <- validate_idempotency(attrs) do
      descriptor = %__MODULE__{
        id: Map.fetch!(attrs, "id"),
        summary: Map.fetch!(attrs, "summary"),
        input_schema: Map.get(attrs, "input_schema", %{"type" => "object"}),
        output_schema: Map.get(attrs, "output_schema", %{"type" => "object"}),
        errors: Map.get(attrs, "errors", []),
        idempotency: Map.get(attrs, "idempotency", "optional"),
        timeout_ms: Map.get(attrs, "timeout_ms", 30_000),
        rate_limit: Map.get(attrs, "rate_limit", "gateway_default"),
        required_scopes: Map.get(attrs, "required_scopes", [])
      }

      {:ok, descriptor}
    end
  end

  @doc "Serialize to a JSON-encodable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = d) do
    %{
      "id" => d.id,
      "summary" => d.summary,
      "input_schema" => d.input_schema,
      "output_schema" => d.output_schema,
      "errors" => d.errors,
      "idempotency" => d.idempotency,
      "timeout_ms" => d.timeout_ms,
      "rate_limit" => d.rate_limit,
      "required_scopes" => d.required_scopes
    }
  end

  defp validate_required(attrs) do
    required = ~w(id summary)
    missing = Enum.filter(required, &(not Map.has_key?(attrs, &1)))

    if missing == [] do
      :ok
    else
      {:error,
       Error.new(:invalid_request, "Operation descriptor missing: #{Enum.join(missing, ", ")}")}
    end
  end

  defp validate_idempotency(attrs) do
    idemp = Map.get(attrs, "idempotency", "optional")

    if idemp in @valid_idempotency do
      :ok
    else
      {:error, Error.new(:invalid_request, "Invalid idempotency: #{inspect(idemp)}")}
    end
  end
end
