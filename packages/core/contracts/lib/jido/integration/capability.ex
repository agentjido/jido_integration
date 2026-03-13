defmodule Jido.Integration.Capability do
  @moduledoc """
  Capability vocabulary for Jido connectors.

  Capabilities are lowercase, dot-separated strings describing what a
  connector can do. Each capability has a status:

  - `native` — fully supported, first-class implementation
  - `fallback` — supported via workaround or polyfill
  - `unsupported` — not available
  - `experimental` — available but unstable

  ## Canonical Vocabulary

  Capabilities are organized by domain:

  - `auth.*` — OAuth2, API key, service account, token refresh
  - `triggers.*` — webhook, polling, schedule, stream
  - `messaging.*` — channel read/write, threading, reactions
  - `devtools.*` — issues, repos, deployments
  - `files.*` — upload, download, list, permissions
  - `crm.*` — contacts, deals read/write
  - `storage.*` — objects, buckets
  - `ai.*` — completions, chat, embeddings

  New capabilities require ADR + version bump.
  """

  @valid_statuses ~w(native fallback unsupported experimental)

  @canonical_capabilities %{
    # Auth
    "auth.oauth2" => "OAuth2 authorization code flow",
    "auth.api_key" => "API key authentication",
    "auth.service_account" => "Service account credentials",
    "auth.session_token" => "Session token authentication",
    "auth.scope_upgrade" => "Dynamic scope upgrade/re-consent",
    "auth.token_refresh" => "Automatic token refresh",
    # Triggers
    "triggers.webhook" => "Inbound webhook ingestion",
    "triggers.polling" => "Periodic polling for changes",
    "triggers.schedule" => "Scheduled/cron triggers",
    "triggers.stream" => "Real-time streaming",
    # Messaging
    "messaging.channel.read" => "Read channel messages",
    "messaging.channel.write" => "Write channel messages",
    "messaging.threading" => "Message threading support",
    "messaging.reactions" => "Message reactions",
    "messaging.attachments" => "File attachments in messages",
    "messaging.read_receipts" => "Read receipt tracking",
    # Email
    "email.send" => "Send email",
    "email.receive" => "Receive email",
    "email.threading" => "Email threading",
    "email.attachments" => "Email attachments",
    # Files
    "files.upload" => "Upload files",
    "files.download" => "Download files",
    "files.list" => "List files",
    "files.permissions" => "Manage file permissions",
    # Calendar
    "calendar.events.read" => "Read calendar events",
    "calendar.events.write" => "Write calendar events",
    "calendar.availability" => "Check availability",
    # CRM
    "crm.contacts.read" => "Read contacts",
    "crm.contacts.write" => "Write contacts",
    "crm.deals.read" => "Read deals",
    "crm.deals.write" => "Write deals",
    # Storage
    "storage.objects.read" => "Read objects",
    "storage.objects.write" => "Write objects",
    "storage.objects.delete" => "Delete objects",
    "storage.buckets.list" => "List buckets",
    # Payments
    "payments.charge" => "Create charges",
    "payments.refund" => "Process refunds",
    "payments.invoices" => "Manage invoices",
    # DevTools
    "devtools.issues.read" => "Read issues",
    "devtools.issues.write" => "Write issues",
    "devtools.repos.read" => "Read repositories",
    "devtools.repos.write" => "Write repositories",
    "devtools.deployments.read" => "Read deployments",
    "devtools.deployments.write" => "Write deployments",
    # Analytics
    "analytics.events.read" => "Read analytics events",
    "analytics.events.write" => "Write analytics events",
    # Database
    "database.query.read" => "Read queries",
    "database.query.write" => "Write queries",
    "database.schema.read" => "Read schema",
    # AI
    "ai.completions" => "Text completions",
    "ai.chat" => "Chat completions",
    "ai.embeddings" => "Generate embeddings",
    "ai.moderation" => "Content moderation",
    "ai.tools" => "Tool use",
    # Browser
    "browser.navigate" => "Navigate browser",
    "browser.screenshot" => "Take screenshots",
    "browser.extract" => "Extract page content",
    # MCP
    "mcp.tools" => "MCP tool protocol",
    "mcp.resources" => "MCP resource protocol"
  }

  @doc "Returns the full canonical capability vocabulary."
  @spec canonical() :: %{String.t() => String.t()}
  def canonical, do: @canonical_capabilities

  @doc "Returns valid status values."
  @spec valid_statuses() :: [String.t()]
  def valid_statuses, do: @valid_statuses

  @doc "Checks if a status string is valid."
  @spec valid_status?(String.t()) :: boolean()
  def valid_status?(status), do: status in @valid_statuses

  @doc "Checks if a capability key is in the canonical vocabulary."
  @spec canonical?(String.t()) :: boolean()
  def canonical?(key), do: Map.has_key?(@canonical_capabilities, key)

  @doc """
  Checks if a capability key is valid (canonical or custom.* namespace).
  """
  @spec valid_key?(String.t()) :: boolean()
  def valid_key?(key) do
    canonical?(key) || String.starts_with?(key, "custom.")
  end

  @doc """
  Validates a capability map. Returns errors for invalid keys or statuses.
  """
  @spec validate(map()) :: :ok | {:error, [{String.t(), String.t()}]}
  def validate(capabilities) when is_map(capabilities) do
    errors =
      Enum.reduce(capabilities, [], fn {key, status}, acc ->
        cond do
          not valid_key?(key) -> [{key, "unknown capability key"} | acc]
          not valid_status?(status) -> [{key, "invalid status: #{status}"} | acc]
          true -> acc
        end
      end)

    case errors do
      [] -> :ok
      errs -> {:error, Enum.reverse(errs)}
    end
  end

  @doc """
  Returns the domain prefix for a capability key.
  """
  @spec domain(String.t()) :: String.t()
  def domain(key) do
    key |> String.split(".") |> List.first()
  end

  @doc """
  Filters capabilities by domain.
  """
  @spec for_domain(map(), String.t()) :: map()
  def for_domain(capabilities, domain_prefix) do
    Map.filter(capabilities, fn {k, _v} ->
      String.starts_with?(k, domain_prefix <> ".")
    end)
  end

  @doc """
  Returns capabilities with the given status.
  """
  @spec with_status(map(), String.t()) :: map()
  def with_status(capabilities, status) do
    Map.filter(capabilities, fn {_k, v} -> v == status end)
  end
end
