defmodule Jido.Integration.V2.Connectors.Notion.Fixtures do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Pristine.Core.Response

  @run_id "run-notion-test"
  @attempt_id "#{@run_id}:1"
  @subject "workspace:acme"
  @credential_ref_id "cred-notion-test"
  @lease_id "lease-notion-test"
  @access_token "secret-notion-access-token"
  @refresh_token "secret-notion-refresh-token"
  @base_url "https://api.notion.com"
  @page_id "00000000-0000-0000-0000-000000000010"
  @created_page_id "00000000-0000-0000-0000-000000000011"
  @data_source_id "00000000-0000-0000-0000-000000000020"
  @block_id "00000000-0000-0000-0000-000000000030"
  @comment_id "00000000-0000-0000-0000-000000000040"
  @published_capability_ids [
    "notion.users.get_self",
    "notion.search.search",
    "notion.pages.create",
    "notion.pages.retrieve",
    "notion.pages.update",
    "notion.blocks.list_children",
    "notion.blocks.append_children",
    "notion.data_sources.query",
    "notion.comments.create"
  ]

  @spec published_capability_ids() :: [String.t()]
  def published_capability_ids, do: @published_capability_ids

  @spec access_token() :: String.t()
  def access_token, do: @access_token

  @spec auth_binding() :: String.t()
  def auth_binding, do: ArtifactBuilder.digest(@access_token)

  @spec data_source_id() :: String.t()
  def data_source_id, do: @data_source_id

  @spec credential_ref() :: CredentialRef.t()
  def credential_ref do
    CredentialRef.new!(credential_ref_attrs())
  end

  @spec credential_ref_attrs() :: map()
  def credential_ref_attrs do
    %{
      id: @credential_ref_id,
      subject: @subject,
      scopes: ["notion.content.read", "notion.content.insert", "notion.content.update"]
    }
  end

  @spec credential_lease() :: CredentialLease.t()
  def credential_lease do
    CredentialLease.new!(credential_lease_attrs())
  end

  @spec credential_lease_attrs() :: map()
  def credential_lease_attrs do
    %{
      lease_id: @lease_id,
      credential_ref_id: @credential_ref_id,
      subject: @subject,
      scopes: [
        "notion.identity.self",
        "notion.content.read",
        "notion.content.insert",
        "notion.content.update",
        "notion.comment.insert"
      ],
      payload: %{
        access_token: @access_token,
        refresh_token: @refresh_token,
        workspace_id: "workspace-acme",
        workspace_name: "Acme Workspace",
        bot_id: "bot-acme"
      },
      issued_at: ~U[2026-03-12 00:00:00Z],
      expires_at: ~U[2026-03-12 00:05:00Z]
    }
  end

  @spec input_for(String.t()) :: map()
  def input_for("notion.users.get_self"), do: %{}

  def input_for("notion.search.search") do
    %{
      query: "Integration docs",
      filter: %{property: "object", value: "page"},
      page_size: 2
    }
  end

  def input_for("notion.pages.create") do
    %{
      parent: %{"data_source_id" => @data_source_id},
      properties: %{
        "Title" => %{
          "title" => [
            %{"type" => "text", "text" => %{"content" => "Deterministic publish page"}}
          ]
        }
      },
      children: [
        %{
          "object" => "block",
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{"type" => "text", "text" => %{"content" => "Published by Jido"}}
            ]
          }
        }
      ]
    }
  end

  def input_for("notion.pages.retrieve"), do: %{page_id: @page_id}

  def input_for("notion.pages.update") do
    %{
      page_id: @page_id,
      archived: false,
      properties: %{
        "Title" => %{
          "title" => [
            %{"type" => "text", "text" => %{"content" => "Deterministic publish page v2"}}
          ]
        }
      }
    }
  end

  def input_for("notion.blocks.list_children"), do: %{block_id: @block_id, page_size: 2}

  def input_for("notion.blocks.append_children") do
    %{
      block_id: @block_id,
      children: [
        %{
          "object" => "block",
          "type" => "bulleted_list_item",
          "bulleted_list_item" => %{
            "rich_text" => [
              %{"type" => "text", "text" => %{"content" => "Deterministic child block"}}
            ]
          }
        }
      ]
    }
  end

  def input_for("notion.data_sources.query") do
    %{
      data_source_id: @data_source_id,
      filter: %{
        property: "Status",
        status: %{
          equals: "Published"
        }
      },
      sorts: [
        %{
          property: "Title",
          direction: "ascending"
        }
      ],
      page_size: 1
    }
  end

  def input_for("notion.comments.create") do
    %{
      parent: %{"page_id" => @page_id},
      rich_text: [
        %{"type" => "text", "text" => %{"content" => "Deterministic comment"}}
      ]
    }
  end

  @spec output_data(String.t()) :: map()
  def output_data("notion.users.get_self") do
    %{
      "object" => "user",
      "id" => "00000000-0000-0000-0000-000000000001",
      "name" => "Integration Bot",
      "type" => "bot",
      "bot" => %{
        "owner" => %{"type" => "workspace", "workspace" => true},
        "workspace_name" => "Acme Workspace"
      }
    }
  end

  def output_data("notion.search.search") do
    %{
      "object" => "list",
      "results" => [
        %{"object" => "page", "id" => @page_id},
        %{"object" => "page", "id" => @created_page_id}
      ],
      "next_cursor" => nil,
      "has_more" => false
    }
  end

  def output_data("notion.pages.create") do
    %{
      "object" => "page",
      "id" => @created_page_id,
      "archived" => false,
      "in_trash" => false,
      "url" => "https://www.notion.so/#{@created_page_id}",
      "parent" => %{"type" => "data_source_id", "data_source_id" => @data_source_id}
    }
  end

  def output_data("notion.pages.retrieve") do
    %{
      "object" => "page",
      "id" => @page_id,
      "archived" => false,
      "in_trash" => false,
      "url" => "https://www.notion.so/#{@page_id}",
      "parent" => %{"type" => "data_source_id", "data_source_id" => @data_source_id},
      "properties" => %{
        "Title" => %{
          "id" => "title",
          "type" => "title",
          "title" => [
            %{"type" => "text", "plain_text" => "Deterministic publish page"}
          ]
        }
      }
    }
  end

  def output_data("notion.pages.update") do
    %{
      "object" => "page",
      "id" => @page_id,
      "archived" => false,
      "in_trash" => false,
      "parent" => %{"type" => "data_source_id", "data_source_id" => @data_source_id},
      "last_edited_by" => %{"object" => "user", "id" => "00000000-0000-0000-0000-000000000001"},
      "properties" => %{
        "Title" => %{
          "id" => "title",
          "type" => "title",
          "title" => [
            %{"type" => "text", "plain_text" => "Deterministic publish page v2"}
          ]
        }
      }
    }
  end

  def output_data("notion.blocks.list_children") do
    %{
      "object" => "list",
      "results" => [
        %{"object" => "block", "id" => @block_id, "type" => "paragraph"},
        %{"object" => "block", "id" => "#{@block_id}-child", "type" => "to_do"}
      ],
      "next_cursor" => nil,
      "has_more" => false
    }
  end

  def output_data("notion.blocks.append_children") do
    %{
      "object" => "list",
      "results" => [
        %{"object" => "block", "id" => "#{@block_id}-appended", "type" => "bulleted_list_item"}
      ]
    }
  end

  def output_data("notion.data_sources.query") do
    %{
      "object" => "list",
      "results" => [
        %{
          "object" => "page",
          "id" => @page_id,
          "parent" => %{"data_source_id" => @data_source_id},
          "properties" => %{
            "Status" => %{
              "id" => "status",
              "type" => "status",
              "status" => %{"name" => "Published"}
            },
            "Title" => %{
              "id" => "title",
              "type" => "title",
              "title" => [
                %{"type" => "text", "plain_text" => "Deterministic publish page"}
              ]
            }
          }
        }
      ],
      "next_cursor" => nil,
      "has_more" => false
    }
  end

  def output_data("notion.data_sources.retrieve") do
    %{
      "object" => "data_source",
      "id" => @data_source_id,
      "title" => [
        %{"type" => "text", "plain_text" => "Publishing Queue"}
      ],
      "properties" => %{
        "Status" => %{
          "id" => "status",
          "name" => "Status",
          "type" => "status",
          "status" => %{
            "options" => [
              %{"id" => "status-published", "name" => "Published"}
            ]
          }
        },
        "Title" => %{
          "id" => "title",
          "name" => "Title",
          "type" => "title",
          "title" => %{}
        }
      }
    }
  end

  def output_data("notion.comments.create") do
    %{
      "object" => "comment",
      "id" => @comment_id,
      "discussion_id" => "00000000-0000-0000-0000-000000000041",
      "parent" => %{"page_id" => @page_id},
      "created_by" => %{"object" => "user", "type" => "bot"}
    }
  end

  @spec request_url(String.t()) :: String.t()
  def request_url("notion.users.get_self"), do: "#{@base_url}/v1/users/me"
  def request_url("notion.search.search"), do: "#{@base_url}/v1/search"
  def request_url("notion.pages.create"), do: "#{@base_url}/v1/pages"
  def request_url("notion.pages.retrieve"), do: "#{@base_url}/v1/pages/#{@page_id}"
  def request_url("notion.pages.update"), do: "#{@base_url}/v1/pages/#{@page_id}"

  def request_url("notion.data_sources.retrieve"),
    do: "#{@base_url}/v1/data_sources/#{@data_source_id}"

  def request_url("notion.blocks.list_children"),
    do: "#{@base_url}/v1/blocks/#{@block_id}/children"

  def request_url("notion.blocks.append_children"),
    do: "#{@base_url}/v1/blocks/#{@block_id}/children"

  def request_url("notion.data_sources.query"),
    do: "#{@base_url}/v1/data_sources/#{@data_source_id}/query"

  def request_url("notion.comments.create"), do: "#{@base_url}/v1/comments"

  @spec execution_context(String.t(), keyword()) :: map()
  def execution_context(_capability_id, opts \\ []) do
    notion_client = Keyword.get(opts, :notion_client, [])

    %{
      run_id: @run_id,
      attempt_id: @attempt_id,
      credential_ref: credential_ref(),
      credential_lease: credential_lease(),
      policy_inputs: %{
        execution: %{
          runtime_class: :direct,
          sandbox: %{
            level: :standard,
            egress: :restricted,
            approvals: :auto,
            allowed_tools: []
          }
        }
      },
      opts: %{notion_client: notion_client}
    }
  end

  @spec conformance_context() :: map()
  def conformance_context do
    %{
      run_id: "run-notion-conformance",
      attempt_id: "run-notion-conformance:1",
      opts: %{notion_client: [transport: Jido.Integration.V2.Connectors.Notion.FixtureTransport]}
    }
  end

  @spec not_found_error() :: {:ok, Response.t()}
  def not_found_error do
    {:ok,
     %Response{
       status: 404,
       headers: %{
         "content-type" => "application/json",
         "authorization" => "Bearer #{@access_token}"
       },
       body:
         Jason.encode!(%{
           "code" => "object_not_found",
           "message" => "Page was not found",
           "request_id" => "req-notion-missing",
           "access_token" => @access_token,
           "additional_data" => %{
             "refresh_token" => @refresh_token
           }
         })
     }}
  end

  @spec response_for_request(map()) :: {:ok, Response.t()}
  def response_for_request(request) do
    url = Map.fetch!(request, :url)
    path = URI.parse(url).path

    request
    |> Map.fetch!(:method)
    |> capability_id_for_request(path)
    |> output_data()
    |> ok_response()
  end

  defp ok_response(body) do
    {:ok,
     %Response{
       status: 200,
       headers: %{"content-type" => "application/json"},
       body: Jason.encode!(body)
     }}
  end

  defp capability_id_for_request(:get, "/v1/users/me"), do: "notion.users.get_self"
  defp capability_id_for_request(:post, "/v1/search"), do: "notion.search.search"
  defp capability_id_for_request(:post, "/v1/pages"), do: "notion.pages.create"
  defp capability_id_for_request(:get, "/v1/pages/#{@page_id}"), do: "notion.pages.retrieve"
  defp capability_id_for_request(:patch, "/v1/pages/#{@page_id}"), do: "notion.pages.update"

  defp capability_id_for_request(:get, "/v1/data_sources/#{@data_source_id}"),
    do: "notion.data_sources.retrieve"

  defp capability_id_for_request(:get, "/v1/blocks/#{@block_id}/children"),
    do: "notion.blocks.list_children"

  defp capability_id_for_request(:patch, "/v1/blocks/#{@block_id}/children"),
    do: "notion.blocks.append_children"

  defp capability_id_for_request(:post, "/v1/data_sources/#{@data_source_id}/query"),
    do: "notion.data_sources.query"

  defp capability_id_for_request(:post, "/v1/comments"), do: "notion.comments.create"
end
