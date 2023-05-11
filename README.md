# Ecto.InstaShard

[![Hex.pm](https://img.shields.io/hexpm/v/ecto_instashard.svg?style=flat-square)](https://hex.pm/packages/ecto_instashard)
[![Hex.pm](https://img.shields.io/hexpm/dt/ecto_instashard.svg?style=flat-square)](https://hex.pm/packages/ecto_instashard)

> Dynamic Instagram-like PostgreSQL sharding with Ecto

This library provides PostgreSQL physical (database) and logical (PostgreSQL schemas) sharding following [Instagram's pattern](http://media.postgresql.org/sfpug/instagram_sfpug.pdf).

Documentation: http://hexdocs.pm/ecto_instashard/

## Main Features
- Unlimited databases and logical shards (PostgreSQL schemas). Ecto Repository modules are generated dynamically – according to sharding configuration.
- Id hashing to choose the related shard.
- Functions to get the dynamic repository related to a hashed id.
- Extract the shard id from a given item id.
- Functions to run queries in the correct physical and logical shard for a given item id.
- Support to multiple sharded PostgreSQL clusters.
- Dynamic creation of sharded schemas, `next_id` functions and tables (by providing the SQL scripts).

Your sharded id column must be based on Instagram's `next_id` function. Each logical shard must have its own function. See [Database Scripts and Migrations](#scripts) below to see how the functions and shard can be generated dynamically.

## Repositories
An Ecto repository is created dynamically for each physical database provided as `Ecto.InstaShard.Repositories.[ShardName].N`, where N >= 0, representing the physical database position.

## How to Use Ecto.InstaShard in an Application

Along with the following documentation, you can also see example configuration and usage in the tests.

### Installation
Add `ecto_instashard` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:ecto_instashard, "~> 0.6"}]
end
```

### Repository Configuration
Add the Ecto **config data** for the repositories that you want to load and connect to with your application into your project `#{env}.exs` files.

You have to specify details about the physical databases in a `List` and then details about the logical shards. The databases list contains individual Ecto config keyword lists.

As an example, consider a Chat Application (`:chat_app`) that will shard chat messages:

```elixir
message_databases = [
  [
    adapter: Ecto.Adapters.Postgres,
    username: "postgres",
    password: "pass",
    database: "messages_0",
    hostname: "localhost",
    pool_size: 5
  ],
  [
    adapter: Ecto.Adapters.Postgres,
    username: "postgres",
    password: "pass",
    database: "messages_1",
    hostname: "localhost",
    pool_size: 5
  ]
]
```

Then provide the physical databases config list and logical shard details to the application config key `:message_databases`:

```elixir
config :chat_app, :message_databases, [
  databases: message_databases,
  count: Enum.count(message_databases),
  logical_shards: 2048,
  mapping: 1024
]
```

Sharded config keys in details:

- **databases**: list of physical databases.
- **count**: amount of physical databases.
- **logical_shards** amount of logical shards distributed across the physical databases (must be an even number).
- **mapping**: amount of logical shards per physical database (must be an even number).

If you are only using sharded repositories, at the bottom of your config set:

```elixir
config :chat_app, ecto_repos: []
```

If you also have normal Ecto repositories in your application, you can configure and use them as you always do, example:

```elixir
config :chat_app, ecto_repos: [ChatApp.Repositories.Accounts]
```

You can also define multiple sharded tables and even separate sharded cluster configuration (i.e. a cluster sharding messages and another cluster sharding upload data).

### Shard Module
Create a module for each of the sharded clusters/table that you need. The module must use `Ecto.InstaShard.Sharding.Setup` passing the necessary configuration.

Example:

```elixir
defmodule ChatApp.Shards.Messages do
  use Ecto.InstaShard.Sharding.Setup, config: [
    config_key: :message_databases,
    app_name: Mix.Project.config[:app],
    base_module_name: ChatApp.ShardedRepositories,
    # [base_module].[name][physical shard], i.e. ChatApp.ShardedRepositories.Messages0
    name: "Messages",
    # the sharded table
    table: "messages",
    scripts: [:messages],
    worker_name: ChatApp.Repositories.Messages,
    supervisor_name: ChatApp.Repositories.MessagesSupervisor
  ]
end
```

### Add the Shard dynamic Ecto Repository to your Supervisor tree

Include the dynamic supervisor related to your Shards into your Supervisor tree using `[ShardModule].include_repository_supervisor`.

```elixir
defmodule ChatApp do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = []
    |> ChatApp.Shards.Messages.include_repository_supervisor
    # Your other children

    opts = [strategy: :one_for_one, name: ChatApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### <a name="scripts"></a>Database Scripts and Migrations
InstaShard can create your sharded tables and dynamic PostgreSQL schemas if you provide the related SQL scripts. Each DDL command must be separated by two blank lines.

Replacement strings:
- `$shard_pos$`: logical shard position.
- `$shard_name$`: logical shard name, example: `shard0`.
- `$shard$`: logical shard name followed by dot `.`, example: `shard0.`. Usage: `$shard$some_table_name`.

Save the scripts in the folder `scripts` in your application and fill the list of SQL scripts as atoms in the Shard configuration, in the `scripts` key (as per previous example).

Examples of scripts (these scripts are also inside `test/scripts`):

```sql
CREATE SCHEMA $shard_name$;

CREATE SEQUENCE $shard_name$.message_seq;

CREATE OR REPLACE FUNCTION $shard_name$.next_id(OUT result bigint) AS $$
DECLARE
    our_epoch bigint := 1314220021721;
    seq_id bigint;
    now_millis bigint;
    shard_id int := $shard_pos$;
    max_shard_id bigint := 2048;
BEGIN
    SELECT nextval('$shard_name$.message_seq') % max_shard_id INTO seq_id;
    SELECT FLOOR(EXTRACT(EPOCH FROM clock_timestamp()) * 1000) INTO now_millis;
    result := (now_millis - our_epoch) << 23;
    result := result | (shard_id << 10);
    result := result | (seq_id);
END;
$$ LANGUAGE PLPGSQL;

CREATE TABLE $shard_name$.messages (
  id bigint not null default $shard_name$.next_id(),
  user_id int not null,
  message text NOT NULL,
  inserted_at timestamp with time zone default now() not null,
  PRIMARY KEY(id)
);
```

To run the scripts and create the shards, call `[ShardModule].check_tables_exists`.

Example:

```elixir
ChatApp.Shards.Messages.check_tables_exists
```

You can create a Mix task to run the command as a migration. Example:

```elixir
# lib/mix/tasks/chat_app.message_tables.ex
defmodule Mix.Tasks.ChatApp.MessageTables do
  use Mix.Task

  def run(_) do
    Mix.Task.run "app.start", []
    ChatApp.Shards.Messages.check_tables_exists
  end
end
```

Run as `mix chat_app.message_tables`.

### Modules Usage
Helper functions are provided to allow consistent access across the physical and logical shards, by hashing the `user_id` owner of the operation/owner of the data. You must not manually call the sharded repository modules, i.e. `Ecto.InstaShard.Repositories.Messages1.insert(...)`, instead, the correct repository and shard is decided by helper functions that hash the `user_id` related to the operation.

#### Get the Ecto Repository Module for a User Id
Call `[ShardModule].repository(user_id)` . Example:

```elixir
repository = ChatApp.Shards.Messages.repository(message.user_id)
```

#### Run include, update and delete for a User Id
Use the helper functions included in the modules `Ecto.InstaShard.Shards.[Shard]` to perform operations in the correct shard for a user id.

- add_query_prefix/2 (to add the related user_id sharded PostgreSQL schema name to the table name)
- sharded_insert/3, sharded_select_query/3, sharded_query/2, sharded_query_all/2, sharded_query_one/2
- insert_all/3, insert_all/4 (supports schemaless changesets: `embedded_schema`)
- update_all/4, update_all/5, update_with_query/4
- delete_all/3, delete_all/4, delete_with_query/4
- get_all/4

Examples:

```elixir
defmodule Message do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :user_id, :integer
    field :message, :map
  end
end

{_, [%{id: id}]} = ChatApp.Shards.Messages.sharded_insert(user.id, changeset.changes, returning: [:id])
ChatApp.Shards.Messages.update_all(user.id, [id: id],
  [message: %{"content" => "foo"}]
)
ChatApp.Shards.Messages.delete_all(user.id, [id: id])
```

#### Run raw sql queries for a User Id
Call `[ShardModule].run_sharded(user_id, sql)`.

#### Get the shard name, shard number and table name for a User Id
Use the helper functions included in the shard module:

- shard/1
- shard_name/1
- table/2, table/3

## TODO

- [ ] Example project
- [ ] Helper functions documentation
- [ ] Helper functions in a separate macro
- [X] Support DDL in a single file instead of multiple files

## License

   Copyright 2016 Alfred Reinold Baudisch

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
