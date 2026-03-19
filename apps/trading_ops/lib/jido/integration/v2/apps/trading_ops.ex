defmodule Jido.Integration.V2.Apps.TradingOps do
  @moduledoc """
  Thin reference app that composes the public platform packages into one
  reviewable trading-ops workflow.
  """

  alias Jido.Integration.V2, as: V2
  alias Jido.Integration.V2.Connectors.CodexCli
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.MarketData
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Ingress
  alias Jido.Integration.V2.Ingress.Definition
  alias Jido.Integration.V2.TargetDescriptor

  @market_target_id "target-trading-ops-market-feed"
  @analyst_target_id "target-trading-ops-analyst-session"
  @ops_target_id "target-trading-ops-operator-saas"

  @market_sandbox %{
    level: :standard,
    egress: :blocked,
    approvals: :auto,
    allowed_tools: ["market.feed.pull"]
  }

  @analyst_sandbox %{
    level: :strict,
    egress: :restricted,
    approvals: :manual,
    file_scope: "/workspaces/codex_cli",
    allowed_tools: ["codex.exec.session"]
  }

  @ops_sandbox %{
    level: :standard,
    egress: :restricted,
    approvals: :auto,
    allowed_tools: ["github.api.issue.create"]
  }

  @type provisioned_resource :: %{
          install: Jido.Integration.V2.Auth.Install.t(),
          connection: Jido.Integration.V2.Auth.Connection.t()
        }

  @type connection_views :: %{
          market_data: provisioned_resource(),
          analyst: provisioned_resource(),
          operator: provisioned_resource()
        }

  @type target_views :: %{
          market_data: TargetDescriptor.t(),
          analyst: TargetDescriptor.t(),
          operator: TargetDescriptor.t()
        }

  @type stack :: %{
          tenant_id: String.t(),
          actor_id: String.t(),
          installs: %{
            market_data: Jido.Integration.V2.Auth.Install.t(),
            analyst: Jido.Integration.V2.Auth.Install.t(),
            operator: Jido.Integration.V2.Auth.Install.t()
          },
          connections: connection_views(),
          targets: target_views()
        }

  @type workflow_step :: %{
          run: Jido.Integration.V2.Run.t(),
          attempt: Jido.Integration.V2.Attempt.t(),
          output: map()
        }

  @type workflow :: %{
          trigger: %{
            status: :accepted | :duplicate,
            trigger: Jido.Integration.V2.TriggerRecord.t(),
            run: Jido.Integration.V2.Run.t()
          },
          market_pull: workflow_step(),
          analyst_session: workflow_step(),
          escalation_issue: workflow_step(),
          connections: connection_views(),
          targets: target_views()
        }

  @spec bootstrap_reference_stack(map()) :: {:ok, stack()}
  def bootstrap_reference_stack(attrs \\ %{}) do
    tenant_id = Map.get(attrs, :tenant_id, "tenant-trading-ops")
    actor_id = Map.get(attrs, :actor_id, "trading-ops-operator")
    now = Map.get(attrs, :now, Contracts.now())

    register_connectors()
    targets = announce_reference_targets()

    market_data =
      provision_resource(
        "market_data",
        tenant_id,
        actor_id,
        "desk-feed",
        ["market:read"],
        %{api_key: "market-demo"},
        now
      )

    analyst =
      provision_resource(
        "codex_cli",
        tenant_id,
        actor_id,
        "desk-analyst",
        ["session:execute"],
        %{access_token: "codex-demo"},
        now
      )

    operator =
      provision_resource(
        "github",
        tenant_id,
        actor_id,
        "desk-operator",
        ["repo"],
        %{access_token: "gho-demo", refresh_token: "ghr-demo"},
        now
      )

    {:ok,
     %{
       tenant_id: tenant_id,
       actor_id: actor_id,
       installs: %{
         market_data: market_data.install,
         analyst: analyst.install,
         operator: operator.install
       },
       connections: %{
         market_data: market_data,
         analyst: analyst,
         operator: operator
       },
       targets: targets
     }}
  end

  @spec run_market_review(stack(), map()) :: {:ok, workflow()} | {:error, term()}
  def run_market_review(%{tenant_id: tenant_id, actor_id: actor_id} = stack, attrs)
      when is_map(attrs) do
    trigger_request = market_signal_request(tenant_id, attrs)
    trigger_definition = market_signal_definition()

    with {:ok, trigger} <- Ingress.admit_poll(trigger_request, trigger_definition),
         {:ok, market_target} <- choose_target("market.ticks.pull", :stream),
         {:ok, analyst_target} <- choose_target("codex.exec.session", :session),
         {:ok, ops_target} <- choose_target("github.issue.create", :direct),
         {:ok, market_pull} <-
           V2.invoke(
             "market.ticks.pull",
             %{
               symbol: Map.fetch!(attrs, :symbol),
               limit: Map.get(attrs, :limit, 2),
               venue: Map.get(attrs, :venue, "CME")
             },
             invoke_opts(
               stack.connections.market_data.connection.connection_id,
               tenant_id,
               actor_id,
               "market.ticks.pull",
               @market_sandbox,
               market_target.target_id
             )
           ),
         {:ok, analyst_session} <-
           V2.invoke(
             "codex.exec.session",
             %{prompt: analyst_prompt(trigger, market_pull.output, attrs)},
             invoke_opts(
               stack.connections.analyst.connection.connection_id,
               tenant_id,
               actor_id,
               "codex.exec.session",
               @analyst_sandbox,
               analyst_target.target_id
             )
           ),
         {:ok, escalation_issue} <-
           V2.invoke(
             "github.issue.create",
             %{
               repo: Map.get(attrs, :issue_repo, "trading/ops-review"),
               title: issue_title(attrs),
               body: issue_body(trigger, market_pull.output, analyst_session.output)
             },
             invoke_opts(
               stack.connections.operator.connection.connection_id,
               tenant_id,
               actor_id,
               "github.issue.create",
               @ops_sandbox,
               ops_target.target_id
             )
           ) do
      {:ok,
       %{
         trigger: trigger,
         market_pull: market_pull,
         analyst_session: analyst_session,
         escalation_issue: escalation_issue,
         connections: stack.connections,
         targets: stack.targets
       }}
    end
  end

  @spec review_packet(workflow()) :: {:ok, map()}
  def review_packet(%{
        trigger: trigger,
        market_pull: market_pull,
        analyst_session: analyst_session,
        escalation_issue: escalation_issue,
        connections: connections,
        targets: targets
      }) do
    {:ok,
     %{
       trigger: trigger,
       connections: %{
         market_data: fetch_connection!(connections.market_data.connection.connection_id),
         analyst: fetch_connection!(connections.analyst.connection.connection_id),
         operator: fetch_connection!(connections.operator.connection.connection_id)
       },
       targets: %{
         market_data: fetch_target!(targets.market_data.target_id),
         analyst: fetch_target!(targets.analyst.target_id),
         operator: fetch_target!(targets.operator.target_id)
       },
       runs: %{
         market_pull: review_surface(market_pull),
         analyst_session: review_surface(analyst_session),
         escalation_issue: review_surface(escalation_issue)
       }
     }}
  end

  defp register_connectors do
    Enum.each([MarketData, CodexCli, GitHub], fn connector ->
      :ok = V2.register_connector(connector)
    end)
  end

  defp announce_reference_targets do
    descriptors = %{
      market_data:
        target_descriptor(
          @market_target_id,
          "market.ticks.pull",
          :stream,
          "integration_stream_bridge",
          "/srv/trading_ops/feeds"
        ),
      analyst:
        target_descriptor(
          @analyst_target_id,
          "codex.exec.session",
          :session,
          "integration_session_bridge",
          "/srv/trading_ops/analyst"
        ),
      operator:
        target_descriptor(
          @ops_target_id,
          "github.issue.create",
          :direct,
          "direct-runtime",
          "/srv/trading_ops/operator"
        )
    }

    Enum.each(Map.values(descriptors), fn descriptor ->
      :ok = V2.announce_target(descriptor)
    end)

    descriptors
  end

  defp target_descriptor(target_id, capability_id, runtime_class, feature_id, workspace_root) do
    runtime_extensions =
      case runtime_class do
        :direct -> %{}
        _other -> %{"runtime" => %{"driver" => feature_id}}
      end

    TargetDescriptor.new!(%{
      target_id: target_id,
      capability_id: capability_id,
      runtime_class: runtime_class,
      version: "1.0.0",
      features: %{
        feature_ids: [feature_id, capability_id],
        runspec_versions: ["1.0.0"],
        event_schema_versions: ["1.0.0"]
      },
      constraints: %{workspace_root: workspace_root},
      health: :healthy,
      location: %{mode: :beam, workspace_root: workspace_root, region: "test"},
      extensions: runtime_extensions
    })
  end

  defp provision_resource(connector_id, tenant_id, actor_id, subject, scopes, secret, now) do
    {:ok, %{install: install, connection: connection}} =
      V2.start_install(connector_id, tenant_id, %{
        actor_id: actor_id,
        auth_type: auth_type_for(secret),
        subject: subject,
        requested_scopes: scopes,
        now: now
      })

    {:ok, _completed_install} =
      V2.complete_install(install.install_id, %{
        subject: subject,
        granted_scopes: scopes,
        secret: secret,
        expires_at: expires_at_for(secret, now),
        now: now
      })

    %{
      install: fetch_install!(install.install_id),
      connection: fetch_connection!(connection.connection_id)
    }
  end

  defp market_signal_definition do
    Definition.new!(%{
      source: :poll,
      connector_id: "market_data",
      trigger_id: "desk.alert",
      capability_id: "market.ticks.pull",
      signal_type: "trading_ops.market.alert",
      signal_source: "/reference_apps/trading_ops/desk.alert",
      dedupe_ttl_seconds: 86_400,
      validator: &validate_market_signal/1
    })
  end

  defp market_signal_request(tenant_id, attrs) do
    now = Map.get(attrs, :observed_at, Contracts.now())

    %{
      tenant_id: tenant_id,
      external_id: Map.get(attrs, :external_id, "#{Map.fetch!(attrs, :symbol)}-alert-1"),
      partition_key: Map.fetch!(attrs, :symbol),
      cursor: Map.get(attrs, :cursor, "cursor-1"),
      last_event_id: Map.get(attrs, :last_event_id, "event-1"),
      last_event_time: now,
      event: %{
        symbol: Map.fetch!(attrs, :symbol),
        price: Map.fetch!(attrs, :price),
        threshold: Map.fetch!(attrs, :threshold),
        direction: Map.get(attrs, :direction, "above")
      }
    }
  end

  defp validate_market_signal(%{symbol: symbol, price: price, threshold: threshold})
       when is_binary(symbol) and is_number(price) and is_number(threshold),
       do: :ok

  defp validate_market_signal(%{"symbol" => symbol, "price" => price, "threshold" => threshold})
       when is_binary(symbol) and is_number(price) and is_number(threshold),
       do: :ok

  defp validate_market_signal(_payload), do: {:error, :invalid_market_signal}

  defp choose_target(capability_id, runtime_class) do
    case V2.compatible_targets(%{
           capability_id: capability_id,
           runtime_class: runtime_class,
           version_requirement: "~> 1.0",
           accepted_runspec_versions: ["1.0.0"],
           accepted_event_schema_versions: ["1.0.0"]
         }) do
      [%{target: target} | _rest] -> {:ok, target}
      [] -> {:error, {:no_compatible_target, capability_id}}
    end
  end

  defp invoke_opts(connection_id, tenant_id, actor_id, capability_id, sandbox, target_id) do
    [
      connection_id: connection_id,
      actor_id: actor_id,
      tenant_id: tenant_id,
      environment: :prod,
      allowed_operations: [capability_id],
      sandbox: sandbox,
      target_id: target_id
    ]
  end

  defp analyst_prompt(trigger, market_output, attrs) do
    symbol = Contracts.get(trigger.trigger.payload, :symbol)
    price = Contracts.get(trigger.trigger.payload, :price)
    threshold = Contracts.get(trigger.trigger.payload, :threshold)

    [
      "Prepare an operator review for #{symbol}.",
      "Observed price #{price} breached threshold #{threshold}.",
      "Recent cursor: #{market_output.cursor}.",
      "Draft guidance with two concrete risk checks.",
      "Desk note: #{Map.get(attrs, :desk_note, "paper review only")}."
    ]
    |> Enum.join(" ")
  end

  defp issue_title(attrs) do
    "#{Map.fetch!(attrs, :symbol)} alert review for trading ops"
  end

  defp issue_body(trigger, market_output, analyst_output) do
    symbol = Contracts.get(trigger.trigger.payload, :symbol)
    price = Contracts.get(trigger.trigger.payload, :price)
    threshold = Contracts.get(trigger.trigger.payload, :threshold)
    direction = Contracts.get(trigger.trigger.payload, :direction)

    """
    Market alert for #{symbol}

    Signal:
    - price: #{price}
    - threshold: #{threshold}
    - direction: #{direction}

    Feed review:
    - venue: #{market_output.venue}
    - cursor: #{market_output.cursor}
    - items: #{length(market_output.items)}

    Analyst reply:
    #{analyst_output.reply}
    """
    |> String.trim()
  end

  defp review_surface(step) do
    %{
      run: fetch_run!(step.run.run_id),
      attempt: fetch_attempt!(step.attempt.attempt_id),
      events: V2.events(step.run.run_id),
      artifacts: V2.run_artifacts(step.run.run_id),
      output: step.output
    }
  end

  defp fetch_install!(install_id) do
    case V2.fetch_install(install_id) do
      {:ok, install} -> install
      {:error, reason} -> raise KeyError, key: install_id, term: reason
    end
  end

  defp fetch_connection!(connection_id) do
    case V2.connection_status(connection_id) do
      {:ok, connection} -> connection
      {:error, reason} -> raise KeyError, key: connection_id, term: reason
    end
  end

  defp fetch_run!(run_id) do
    case V2.fetch_run(run_id) do
      {:ok, run} -> run
      :error -> raise KeyError, key: run_id, term: :run
    end
  end

  defp fetch_attempt!(attempt_id) do
    case V2.fetch_attempt(attempt_id) do
      {:ok, attempt} -> attempt
      :error -> raise KeyError, key: attempt_id, term: :attempt
    end
  end

  defp fetch_target!(target_id) do
    case V2.fetch_target(target_id) do
      {:ok, target} -> target
      :error -> raise KeyError, key: target_id, term: :target
    end
  end

  defp auth_type_for(secret) do
    if Map.has_key?(secret, :api_key), do: :api_key, else: :oauth2
  end

  defp expires_at_for(secret, now) do
    if Map.has_key?(secret, :api_key), do: nil, else: DateTime.add(now, 7 * 24 * 3_600, :second)
  end
end
