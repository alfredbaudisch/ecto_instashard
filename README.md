# Ecto.InstaShard

This library provides physical and logical sharded PostgreSQL access following [Instagram's pattern](http://instagram-engineering.tumblr.com/post/10853187575/sharding-ids-at-instagram).

## Main Features
- Unlimited databases and logical shards (PostgreSQL schemas). Ecto Repository modules are generated dynamically – according to sharding configuration.
- Id hashing to choose the related shard.
- Functions to get the dynamic repository related to a hashed id.
- Extract the shard id from a given item id.
- Functions to run queries in the correct physical and logical shard for a given item id.
- Support to multipled sharded clusters.

## Repositories
An Ecto repository is created dynamically for each physical database provided as `Ecto.InstaShard.Repositories.[ShardName].N`, where N >= 0, representing the physical database position.

## How to Use Ecto.InstaShard in an Application

### Installation
Add `ecto_instashard` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:ecto_instashard, "~> 0.1.0"}]
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

If you also have normal Ecto repositories in your application, you can configure and use then as you always do, example:

    ```elixir
    config :chat_app, ecto_repos: [ChatApp.Repositories.Accounts]
    ```

You can also define multiple sharded tables and even separate sharded cluster configuration (i.e. a cluster sharding messages and another cluster sharding upload data).

### Shard Module

Create a module for each of the sharded clusters/table that you need. The module must use `use Ecto.InstaShard.Sharding.Setup` passing the necessary configuration.

Example:

    ```elixir
    defmodule ChatApp.Shards.Messages do
      use Ecto.InstaShard.Sharding.Setup, config: [
        config_key: :message_databases,
        name: "Messages",
        table: "messages",
        system_env: "MESSAGE_DATABASES",
        scripts: [:messages01_schema, :messages02_sequence, :messages03_next_id, :messages04_table],
        worker_name: ChatApp.Repositories.Messages,
        supervisor_name: ChatApp.Repositories.MessagesSupervisor
      ]
    end
    ```

### Database Scripts and Migrations

- Main and Bot Tables: `mix ecto.migrate -r Ecto.InstaShard.Repositories.Main`
- User Data Tables: `mix ecto.migrate -r Ecto.InstaShard.Repositories.Account`
- Sharded message tables (including logical shards): `mix fred_data.message_tables` (for each MIX_ENV)
- Sharded bot data tables (including logical shards): `mix fred_data.bot_data_tables` (for each MIX_ENV)

### Modules Usage
Helper functions are provided to allow consistent access across the physical and logical shards, by hashing the `user_id` owner of the operation/owner of the data. You must not manually call the sharded repository modules, i.e. `Ecto.InstaShard.Repositories.Messages1.insert(...)`, instead, the correct repository and shard is decided by helper functions that hash the `user_id` related to the operation.

#### Get the Ecto Repository Module for a User Id
Call `Ecto.InstaShard.Shards.[Shard].repository(user_id)` . Example:

    ```elixir
    repository = ChatApp.Shards.Messages.repository(message.user_id)
    ```

#### Run include, update and delete for a User Id
Use the helper functions included in the modules `Ecto.InstaShard.Shards.[Shard]` to perform operations in the correct shard for a user id.

- add_query_prefix/2 (to add the related user_id sharded PostgreSQL schema name to the table name)
- sharded_insert/3, sharded_query/3
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

    {_, [%{id: id}]} = Ecto.InstaShard.Shards.Messages.sharded_insert(user.id, changeset.changes, returning: [:id])
    Ecto.InstaShard.Shards.Messages.update_all(user.id, [id: id], [message: %{"content" => "foo"}])
    Ecto.InstaShard.Shards.Messages.delete_all(user.id, [id: id])
    ```

#### Run raw sql queries for a User Id
Call `Ecto.InstaShard.Shards.[Shard].run_sharded(user_id, sql)`.

#### Get the shard name, shard number and table name for a User Id
Use the helper functions included in the module `Ecto.InstaShard.Shards.[Shard]`:

- shard/1
- shard_name/1
- table/2, table/3
