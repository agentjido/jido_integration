defmodule Jido.Integration.ModelInvocation do
  @moduledoc """
  Governed model invocation contracts for the AI execution seam.

  This package is the ref-only contract layer between Mezzanine's AI execution
  engine and Jido Integration's model runtime. It intentionally carries artifact
  refs and hashes rather than raw prompts or provider-native payloads.
  """

  alias __MODULE__.{Receipt, Request, StreamFragment}

  @spec new_request(map() | keyword() | Request.t()) ::
          {:ok, Request.t()} | {:error, Exception.t()}
  defdelegate new_request(attrs), to: Request, as: :new

  @spec new_request!(map() | keyword() | Request.t()) :: Request.t()
  defdelegate new_request!(attrs), to: Request, as: :new!

  @spec new_receipt(map() | keyword() | Receipt.t()) ::
          {:ok, Receipt.t()} | {:error, Exception.t()}
  defdelegate new_receipt(attrs), to: Receipt, as: :new

  @spec new_receipt!(map() | keyword() | Receipt.t()) :: Receipt.t()
  defdelegate new_receipt!(attrs), to: Receipt, as: :new!

  @spec new_stream_fragment(map() | keyword() | StreamFragment.t()) ::
          {:ok, StreamFragment.t()} | {:error, Exception.t()}
  defdelegate new_stream_fragment(attrs), to: StreamFragment, as: :new

  @spec new_stream_fragment!(map() | keyword() | StreamFragment.t()) :: StreamFragment.t()
  defdelegate new_stream_fragment!(attrs), to: StreamFragment, as: :new!
end
