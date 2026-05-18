%{
  deps: %{
    agent_session_manager: %{
      path: "../agent_session_manager",
      github: %{repo: "nshkrdotcom/agent_session_manager", branch: "main"},
      hex: "~> 0.9.2",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    amp_sdk: %{
      path: "../amp_sdk",
      github: %{repo: "nshkrdotcom/amp_sdk", branch: "main"},
      hex: "~> 0.5.0",
      opts: [override: true],
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    cli_subprocess_core: %{
      path: "../cli_subprocess_core",
      github: %{repo: "nshkrdotcom/cli_subprocess_core", branch: "main"},
      hex: "~> 0.1.0",
      opts: [override: true],
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    execution_plane: %{
      path: "../execution_plane/core/execution_plane",
      github: %{
        repo: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "core/execution_plane"
      },
      hex: "~> 0.1.0",
      opts: [override: true],
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    execution_plane_jsonrpc: %{
      path: "../execution_plane/protocols/execution_plane_jsonrpc",
      github: %{
        repo: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "protocols/execution_plane_jsonrpc"
      },
      hex: "~> 0.1.0",
      opts: [override: true],
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    execution_plane_process: %{
      path: "../execution_plane/runtimes/execution_plane_process",
      github: %{
        repo: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "runtimes/execution_plane_process"
      },
      hex: "~> 0.1.0",
      opts: [override: true],
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    github_ex: %{
      path: "../github_ex",
      github: %{repo: "nshkrdotcom/github_ex", branch: "main"},
      hex: "~> 0.1.1",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    ground_plane_persistence_policy: %{
      path: "../ground_plane/core/persistence_policy",
      github: %{
        repo: "nshkrdotcom/ground_plane",
        branch: "main",
        subdir: "core/persistence_policy"
      },
      hex: "~> 0.1.0",
      opts: [override: true],
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    ground_plane_contracts: %{
      path: "../ground_plane/core/ground_plane_contracts",
      github: %{
        repo: "nshkrdotcom/ground_plane",
        branch: "main",
        subdir: "core/ground_plane_contracts"
      },
      hex: "~> 0.1.0",
      opts: [override: true],
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    inference: %{
      path: "../inference/apps/inference",
      github: %{repo: "nshkrdotcom/inference", branch: "main", subdir: "apps/inference"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    jido_action: %{
      hex: "~> 2.2",
      default_order: [:hex],
      publish_order: [:hex]
    },
    linear_sdk: %{
      path: "../linear_sdk",
      github: %{repo: "nshkrdotcom/linear_sdk", branch: "main"},
      hex: "~> 0.2.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    llama_cpp_sdk: %{
      path: "../llama_cpp_sdk",
      github: %{repo: "nshkrdotcom/llama_cpp_sdk", branch: "main"},
      hex: "~> 0.1.0",
      opts: [override: true],
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    notion_sdk: %{
      path: "../notion_sdk",
      github: %{repo: "nshkrdotcom/notion_sdk", branch: "main"},
      hex: "~> 0.2.1",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    prismatic: %{
      path: "../prismatic/apps/prismatic_runtime",
      github: %{repo: "nshkrdotcom/prismatic", branch: "main", subdir: "apps/prismatic_runtime"},
      hex: "~> 0.2.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    pristine: %{
      path: "../pristine/apps/pristine_runtime",
      github: %{repo: "nshkrdotcom/pristine", branch: "main", subdir: "apps/pristine_runtime"},
      hex: "~> 0.2.1",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    req_llm: %{
      hex: "~> 1.9",
      default_order: [:hex],
      publish_order: [:hex]
    },
    self_hosted_inference_core: %{
      path: "../self_hosted_inference_core",
      github: %{repo: "nshkrdotcom/self_hosted_inference_core", branch: "main"},
      hex: "~> 0.1.0",
      opts: [override: true],
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    splode: %{
      hex: "~> 0.3.0",
      default_order: [:hex],
      publish_order: [:hex]
    }
  }
}
