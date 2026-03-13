defmodule Jido.Integration.Connectors.GitHubTest do
  use ExUnit.Case

  defmodule OverrideHttpClient do
    def get(_url, _headers),
      do: {:ok, %{status: 200, body: [%{"id" => 999, "title" => "override"}]}}

    def post(_url, _body, _headers), do: {:error, :not_implemented}
    def patch(_url, _body, _headers), do: {:error, :not_implemented}
  end

  alias Jido.Integration.Connectors.GitHub
  alias Jido.Integration.{Error, Manifest}
  alias Jido.Integration.Test.MockHttpClient

  setup do
    Application.put_env(:jido_integration_github, GitHub, http_client: MockHttpClient)

    on_exit(fn ->
      Application.delete_env(:jido_integration_github, GitHub)
    end)

    :ok
  end

  describe "package boundary" do
    test "loads the connector module from the GitHub package project" do
      beam_path = GitHub |> :code.which() |> List.to_string()

      assert beam_path =~ "/packages/connectors/github/",
             "expected GitHub connector to be compiled from the package, got: #{beam_path}"
    end
  end

  describe "id/0" do
    test "returns string id" do
      assert GitHub.id() == "github"
      assert is_binary(GitHub.id())
    end
  end

  describe "manifest/0" do
    test "returns valid manifest" do
      manifest = GitHub.manifest()
      assert %Manifest{} = manifest
      assert manifest.id == "github"
      assert manifest.display_name == "GitHub"
      assert manifest.vendor == "GitHub, Inc."
      assert manifest.domain == "saas"
      assert manifest.quality_tier == "bronze"
    end

    test "has OAuth2 auth descriptor" do
      manifest = GitHub.manifest()
      assert length(manifest.auth) == 1
      [auth] = manifest.auth
      assert auth.type == "oauth2"
      assert auth.id == "oauth2"
      assert "repo" in auth.scopes
      assert auth.oauth != nil
      assert auth.oauth["grant_type"] == "authorization_code"
    end

    test "has the proving-slice operations" do
      manifest = GitHub.manifest()
      assert length(manifest.operations) == 8
      op_ids = Enum.map(manifest.operations, & &1.id)
      assert "github.list_issues" in op_ids
      assert "github.fetch_issue" in op_ids
      assert "github.create_issue" in op_ids
      assert "github.update_issue" in op_ids
      assert "github.label_issue" in op_ids
      assert "github.create_comment" in op_ids
      assert "github.update_comment" in op_ids
      assert "github.close_issue" in op_ids
    end

    test "has webhook trigger" do
      manifest = GitHub.manifest()
      assert length(manifest.triggers) == 1
      [trigger] = manifest.triggers
      assert trigger.id == "github.webhook.push"
      assert trigger.class == "webhook"
      assert trigger.verification["type"] == "hmac"
      assert trigger.callback_topology == "dynamic_per_install"
    end

    test "has capabilities" do
      manifest = GitHub.manifest()
      assert manifest.capabilities["auth.oauth2"] == "native"
      assert manifest.capabilities["triggers.webhook"] == "native"
      assert manifest.capabilities["devtools.issues.read"] == "native"
      assert manifest.capabilities["devtools.issues.write"] == "native"
    end

    test "all errors match taxonomy" do
      manifest = GitHub.manifest()

      for op <- manifest.operations do
        for error <- op.errors do
          class = error["class"]
          retryability = error["retryability"]

          assert Error.valid_retryability?(class, retryability),
                 "Operation #{op.id}: error class #{class} should have retryability #{Error.default_retryability(String.to_existing_atom(class))} but got #{retryability}"
        end
      end
    end
  end

  describe "validate_config/1" do
    test "accepts valid config" do
      assert {:ok, _} = GitHub.validate_config(%{"owner" => "test", "repo" => "test"})
    end

    test "rejects missing owner" do
      assert {:error, error} = GitHub.validate_config(%{"repo" => "test"})
      assert error.class == :invalid_request
    end
  end

  describe "run/3 - list_issues" do
    test "returns issues on success" do
      issues = [
        %{"id" => 1, "title" => "Bug", "state" => "open"},
        %{"id" => 2, "title" => "Feature", "state" => "open"}
      ]

      MockHttpClient.expect_get({:ok, %{status: 200, body: issues}})

      assert {:ok, result} =
               GitHub.run("github.list_issues", %{"owner" => "test", "repo" => "test"}, [])

      assert result["issues"] == issues
      assert result["total_count"] == 2
    end

    test "returns auth_failed on 401" do
      MockHttpClient.expect_get({:ok, %{status: 401, body: %{}}})

      assert {:error, error} =
               GitHub.run("github.list_issues", %{"owner" => "test", "repo" => "test"}, [])

      assert error.class == :auth_failed
      assert error.code == "github.auth_failed"
    end

    test "returns rate_limited on 403 with rate limit message" do
      MockHttpClient.expect_get(
        {:ok, %{status: 403, body: %{"message" => "API rate limit exceeded"}}}
      )

      assert {:error, error} =
               GitHub.run("github.list_issues", %{"owner" => "test", "repo" => "test"}, [])

      assert error.class == :rate_limited
      assert error.code == "github.rate_limited"
      assert Error.retryable?(error)
    end

    test "returns invalid_request on 404" do
      MockHttpClient.expect_get({:ok, %{status: 404, body: %{}}})

      assert {:error, error} =
               GitHub.run("github.list_issues", %{"owner" => "test", "repo" => "missing"}, [])

      assert error.class == :invalid_request
    end

    test "returns unavailable on network error" do
      MockHttpClient.expect_get({:error, :timeout})

      assert {:error, error} =
               GitHub.run("github.list_issues", %{"owner" => "test", "repo" => "test"}, [])

      assert error.class == :unavailable
      assert Error.retryable?(error)
    end

    test "returns invalid_request when required args are missing" do
      assert {:error, error} = GitHub.run("github.list_issues", %{"repo" => "test"}, [])
      assert error.class == :invalid_request
    end

    test "returns unavailable on unexpected upstream status" do
      MockHttpClient.expect_get({:ok, %{status: 500, body: %{"message" => "server error"}}})

      assert {:error, error} =
               GitHub.run("github.list_issues", %{"owner" => "test", "repo" => "test"}, [])

      assert error.class == :unavailable
    end

    test "supports mocked responses across a task boundary" do
      issues = [%{"id" => 1, "title" => "Task issue", "state" => "open"}]
      MockHttpClient.expect_get({:ok, %{status: 200, body: issues}})

      task =
        Task.async(fn ->
          GitHub.run("github.list_issues", %{"owner" => "test", "repo" => "test"}, [])
        end)

      assert {:ok, result} = Task.await(task)
      assert result["issues"] == issues
    end

    test "allows per-call http_client injection without mutating application env" do
      assert {:ok, result} =
               GitHub.run(
                 "github.list_issues",
                 %{"owner" => "test", "repo" => "test"},
                 http_client: OverrideHttpClient
               )

      assert result["issues"] == [%{"id" => 999, "title" => "override"}]
    end
  end

  describe "run/3 - create_issue" do
    test "creates issue successfully" do
      response = %{
        "id" => 42,
        "number" => 10,
        "url" => "https://api.github.com/repos/test/test/issues/10",
        "html_url" => "https://github.com/test/test/issues/10"
      }

      MockHttpClient.expect_post({:ok, %{status: 201, body: response}})

      assert {:ok, result} =
               GitHub.run(
                 "github.create_issue",
                 %{"owner" => "test", "repo" => "test", "title" => "New Issue"},
                 []
               )

      assert result["id"] == 42
      assert result["number"] == 10
      assert result["html_url"] =~ "github.com"
    end

    test "returns auth_failed on 401" do
      MockHttpClient.expect_post({:ok, %{status: 401, body: %{}}})

      assert {:error, error} =
               GitHub.run(
                 "github.create_issue",
                 %{"owner" => "test", "repo" => "test", "title" => "New"},
                 []
               )

      assert error.class == :auth_failed
    end

    test "returns invalid_request on 422" do
      MockHttpClient.expect_post(
        {:ok, %{status: 422, body: %{"errors" => [%{"message" => "title is too short"}]}}}
      )

      assert {:error, error} =
               GitHub.run(
                 "github.create_issue",
                 %{"owner" => "test", "repo" => "test", "title" => ""},
                 []
               )

      assert error.class == :invalid_request
    end

    test "returns invalid_request when required args are missing" do
      assert {:error, error} = GitHub.run("github.create_issue", %{"owner" => "test"}, [])
      assert error.class == :invalid_request
    end

    test "returns unavailable on unexpected upstream status" do
      MockHttpClient.expect_post({:ok, %{status: 500, body: %{"message" => "server error"}}})

      assert {:error, error} =
               GitHub.run(
                 "github.create_issue",
                 %{"owner" => "test", "repo" => "test", "title" => "New"},
                 []
               )

      assert error.class == :unavailable
    end
  end

  describe "run/3 - fetch_issue" do
    test "fetches an issue successfully" do
      response = %{
        "id" => 42,
        "number" => 10,
        "url" => "https://api.github.com/repos/test/test/issues/10",
        "html_url" => "https://github.com/test/test/issues/10",
        "state" => "open",
        "title" => "Existing issue"
      }

      MockHttpClient.expect_get({:ok, %{status: 200, body: response}})

      assert {:ok, result} =
               GitHub.run(
                 "github.fetch_issue",
                 %{"owner" => "test", "repo" => "test", "issue_number" => 10},
                 []
               )

      assert result["number"] == 10
      assert result["title"] == "Existing issue"
    end

    test "returns invalid_request for unknown issue" do
      MockHttpClient.expect_get({:ok, %{status: 404, body: %{}}})

      assert {:error, error} =
               GitHub.run(
                 "github.fetch_issue",
                 %{"owner" => "test", "repo" => "test", "issue_number" => 10},
                 []
               )

      assert error.class == :invalid_request
    end
  end

  describe "run/3 - update_issue" do
    test "updates issue successfully" do
      response = %{
        "id" => 42,
        "number" => 10,
        "url" => "https://api.github.com/repos/test/test/issues/10",
        "html_url" => "https://github.com/test/test/issues/10",
        "state" => "open",
        "title" => "Updated"
      }

      MockHttpClient.expect_patch({:ok, %{status: 200, body: response}})

      assert {:ok, result} =
               GitHub.run(
                 "github.update_issue",
                 %{
                   "owner" => "test",
                   "repo" => "test",
                   "issue_number" => 10,
                   "title" => "Updated"
                 },
                 []
               )

      assert result["title"] == "Updated"
    end
  end

  describe "run/3 - label_issue" do
    test "adds labels successfully" do
      response = [%{"name" => "bug"}, %{"name" => "triaged"}]

      MockHttpClient.expect_post({:ok, %{status: 200, body: response}})

      assert {:ok, result} =
               GitHub.run(
                 "github.label_issue",
                 %{
                   "owner" => "test",
                   "repo" => "test",
                   "issue_number" => 10,
                   "labels" => ["bug", "triaged"]
                 },
                 []
               )

      assert Enum.map(result["labels"], & &1["name"]) == ["bug", "triaged"]
    end
  end

  describe "run/3 - create_comment" do
    test "creates comment successfully" do
      response = %{
        "id" => 99,
        "url" => "https://api.github.com/repos/test/test/issues/comments/99",
        "html_url" => "https://github.com/test/test/issues/1#issuecomment-99"
      }

      MockHttpClient.expect_post({:ok, %{status: 201, body: response}})

      assert {:ok, result} =
               GitHub.run(
                 "github.create_comment",
                 %{
                   "owner" => "test",
                   "repo" => "test",
                   "issue_number" => 1,
                   "body" => "A comment"
                 },
                 []
               )

      assert result["id"] == 99
    end

    test "returns invalid_request when required args are missing" do
      assert {:error, error} =
               GitHub.run(
                 "github.create_comment",
                 %{"owner" => "test", "repo" => "test"},
                 []
               )

      assert error.class == :invalid_request
    end

    test "returns unavailable on unexpected upstream status" do
      MockHttpClient.expect_post({:ok, %{status: 500, body: %{"message" => "server error"}}})

      assert {:error, error} =
               GitHub.run(
                 "github.create_comment",
                 %{
                   "owner" => "test",
                   "repo" => "test",
                   "issue_number" => 1,
                   "body" => "A comment"
                 },
                 []
               )

      assert error.class == :unavailable
    end
  end

  describe "run/3 - update_comment" do
    test "updates a comment successfully" do
      response = %{
        "id" => 99,
        "url" => "https://api.github.com/repos/test/test/issues/comments/99",
        "html_url" => "https://github.com/test/test/issues/1#issuecomment-99",
        "body" => "Updated comment"
      }

      MockHttpClient.expect_patch({:ok, %{status: 200, body: response}})

      assert {:ok, result} =
               GitHub.run(
                 "github.update_comment",
                 %{
                   "owner" => "test",
                   "repo" => "test",
                   "comment_id" => 99,
                   "body" => "Updated comment"
                 },
                 []
               )

      assert result["body"] == "Updated comment"
    end
  end

  describe "run/3 - close_issue" do
    test "closes an issue successfully" do
      response = %{
        "id" => 42,
        "number" => 10,
        "url" => "https://api.github.com/repos/test/test/issues/10",
        "html_url" => "https://github.com/test/test/issues/10",
        "state" => "closed"
      }

      MockHttpClient.expect_patch({:ok, %{status: 200, body: response}})

      assert {:ok, result} =
               GitHub.run(
                 "github.close_issue",
                 %{"owner" => "test", "repo" => "test", "issue_number" => 10},
                 []
               )

      assert result["state"] == "closed"
    end
  end

  describe "run/3 - unknown operation" do
    test "returns unsupported error" do
      assert {:error, error} = GitHub.run("github.unknown_op", %{}, [])
      assert error.class == :unsupported
    end
  end

  describe "handle_trigger/2" do
    test "normalizes webhook payload" do
      payload = %{
        "headers" => %{
          "x-github-event" => "issues",
          "x-github-delivery" => "delivery-123"
        },
        "body" => %{"action" => "opened", "issue" => %{"number" => 1}}
      }

      assert {:ok, result} = GitHub.handle_trigger("github.webhook.push", payload)
      assert result["event_type"] == "issues"
      assert result["delivery_id"] == "delivery-123"
      assert result["payload"]["action"] == "opened"
    end

    test "returns unsupported for unknown trigger" do
      assert {:error, error} = GitHub.handle_trigger("unknown", %{})
      assert error.class == :unsupported
    end
  end
end
