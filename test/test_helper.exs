ExUnit.start()

message_databases = [
  [
    adapter: Ecto.Adapters.Postgres,
    username: "fred_tester",
    password: "tester_FRED",
    database: "mt1",
    hostname: "localhost",
    port: 5496,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 2,
    ownership_timeout: 30_000
  ],
  [
    adapter: Ecto.Adapters.Postgres,
    username: "fred_tester",
    password: "tester_FRED",
    database: "mt2",
    hostname: "localhost",
    port: 5496,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 2,
    ownership_timeout: 30_000
  ],
  [
    adapter: Ecto.Adapters.Postgres,
    username: "fred_tester",
    password: "tester_FRED",
    database: "mt3",
    hostname: "localhost",
    port: 5496,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 2,
    ownership_timeout: 30_000
  ],
  [
    adapter: Ecto.Adapters.Postgres,
    username: "fred_tester",
    password: "tester_FRED",
    database: "mt4",
    hostname: "localhost",
    port: 5496,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 2,
    ownership_timeout: 30_000
  ]
]

amount_message_databases = Enum.count(message_databases)

Application.put_env(:ecto_instashard, :message_databases, [
  databases: message_databases,
  count: amount_message_databases,
  logical_shards: 8,
  mapping: 2
])

Application.put_env(:ecto_instashard, :ecto_repos, [])

Application.ensure_all_started(:postgrex)

defmodule Ecto.InstaShard.Shards.Messages do
  use Ecto.InstaShard.Sharding.Setup, config: [
    config_key: :message_databases,
    app_name: :ecto_instashard,
    base_module_name: Ecto.InstaShard.ShardedRepositories,
    name: "Messages",
    table: "messages",
    scripts: [:messages],
    worker_name: Ecto.InstaShard.Repositories.Messages,
    supervisor_name: Ecto.InstaShard.Repositories.MessagesSupervisor
  ]
end

children = []
|> Ecto.InstaShard.Shards.Messages.include_repository_supervisor

opts = [strategy: :one_for_one, name: Ecto.InstaShard.ShardSupervisor]

import Supervisor.Spec, warn: false
Supervisor.start_link(children, opts)

defmodule Ecto.InstaShard.TestHelpers do
  def create_message_tables do
    Ecto.InstaShard.Shards.Messages.check_tables_exists("test/scripts")
  end
end
