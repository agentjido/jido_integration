import Config

env = System.get_env()

config :jido_integration_workspace, :env, env
config :agent_session_manager, :env, env
