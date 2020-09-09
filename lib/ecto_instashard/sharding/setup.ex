defmodule Ecto.InstaShard.Sharding.Setup do
  defmacro __using__(opts) do
    config = Keyword.fetch!(opts, :config)

    quote do
      import Ecto.InstaShard.Sharding
      import Logger
      import Ecto.Query

      @app_name unquote(config[:app_name])

      @setup Application.get_env(@app_name, unquote(config[:config_key])) || [
        count: 0
      ]

      unless @setup do
        raise "Config #{unquote(config[:config_key])} can't be nil"
      end

      @base_module_name unquote(config[:base_module_name])
      @mapping @setup[:mapping]
      @repository_name unquote(config[:name])
      @table_name unquote(config[:table])
      @dynamic_init unquote(config[:dynamic_init])

      def include_repository_supervisor(children) do
        count = setup_key(:count)

        if count && count > 0 do
          import Supervisor.Spec, warn: false

          children ++ [
            supervisor(Ecto.InstaShard.Repositories.ShardedSupervisor, [%{
            worker_name: unquote(config[:worker_name]),
            utils: __MODULE__,
            name: unquote(config[:supervisor_name]),
          }], [id: make_ref()])]
        else
          children
        end

      end

      def setup_key(key), do: @setup[key]

      def repositories_to_load do
        for n <- 0..__MODULE__.setup_key(:count) - 1 do
          __MODULE__.create_repository_module(n)
        end
      end

      def logical_to_physical(logical) when logical < @mapping, do: 0
      def logical_to_physical(logical), do: round(Float.floor(logical / @mapping))

      def create_repository_module(position) do
        if logical_to_physical(@setup[:logical_shards] - 1) >= @setup[:count] do
          raise "#{unquote(config[:config_key])}.mapping (#{@mapping}) leads to a mapping higher than the amount of avaialble physical databases (#{@setup[:count]})"
        end

        db = Enum.at(@setup[:databases], position)
        mod = repository_module(position)
        Application.put_env(@app_name, mod, db)

        Ecto.InstaShard.Sharding.create_repository_module(%{
          position: position,
          table: @table_name,
          app_name: @app_name,
          module: mod,
          dynamic_init: @dynamic_init
        })

        ecto_repos = Application.get_env(@app_name, :ecto_repos)
        Application.put_env(@app_name, :ecto_repos, ecto_repos ++ [mod])

        mod
      end

      def repository_module(position) do
        repository_module_name(@base_module_name, @repository_name, position)
      end

      def check_tables_exists(directory \\ "scripts") do
        run_all_shards(fn(n, mod) ->
          case mod.check_tables_exists(n) do
            false -> create_tables(mod, n, directory)
            _ -> nil
          end
        end)
      end

      def sql_all_shards(sql) do
        run_all_shards(fn(n, mod) ->
          Ecto.Adapters.SQL.query!(mod, sql |> String.replace("{shard}", "shard#{n}."))
        end)
      end

      def run_all_shards(run) do
        for n <- 0..@setup[:logical_shards] - 1 do
          mod = repository_module(logical_to_physical(n))
          run.(n, mod)
        end
      end

      def shard(parent_id) do
        rem(Ecto.InstaShard.Sharding.Hashing.item_hash(parent_id), @setup[:logical_shards])
      end

      def shard_name(parent_id), do: "shard#{shard(parent_id)}"
      def shard_name(id, :extract), do: "shard#{Ecto.InstaShard.Sharding.Hashing.extract(id)}"

      def repository(parent_id) do
        repository_from_shard(shard(parent_id))
      end

      def repository_from_shard(shard) do
        physical = logical_to_physical(shard)
        repository_module(physical)
      end

      def create_tables(mod, n, directory) do
        mod.transaction(fn ->
          Enum.map(unquote(config[:scripts]), fn(script) ->
            replace_and_run_script_sql(mod, script, n, directory)
          end)
        end)
      end

      def run_sharded(parent_id, sql) do
        repo = repository(parent_id)
        sql |> repo.run
      end

      def table(parent_id, :tuple), do: table(parent_id, @table_name, :tuple)
      def table(parent_id, :string), do: table(parent_id, @table_name, :string)
      def table(parent_id, table_name, :tuple), do: {shard_name(parent_id), table_name}
      def table(parent_id, table_name, :string), do: "#{shard_name(parent_id)}.#{table_name}"

      defp append_shard_name_to_opts(opts, parent_id), do: opts ++ [{:prefix, shard_name(parent_id)}]

      def sharded_insert(parent_id, changeset, opts) do
        sharded_insert(parent_id, @table_name, changeset, opts)
      end

      def sharded_insert(parent_id, table_name, changeset, opts) do
        insert_all(parent_id, table_name, changeset, opts)
      end

      def insert_all(parent_id, changeset, opts) when is_list(changeset) do
        repository(parent_id).insert_all(@table_name, changeset, opts |> append_shard_name_to_opts(parent_id))
      end

      def insert_all(parent_id, changeset, opts) do
        insert_all(parent_id, [changeset], opts)
      end

      def insert_all(parent_id, table_name, changeset, opts) when is_list(changeset) do
        repository(parent_id).insert_all(table_name, changeset, opts |> append_shard_name_to_opts(parent_id))
      end

      def insert_all(parent_id, table_name, changeset, opts) do
        insert_all(parent_id, table_name, [changeset], opts)
      end

      def sharded_query(parent_id, table_name, where) do
        from(m in table_name, where: ^where)
        |> add_query_prefix(parent_id)
      end

      def add_query_prefix(query, parent_id) do
        %{query | prefix: shard_name(parent_id)}
      end

      def add_query_prefix(query, id, :extract) do
        %{query | prefix: shard_name(id, :extract)}
      end

      def get_all(parent_id, table_name, where, select) do
        from(table_name, where: ^where, select: ^select)
        |> do_get_all(parent_id)
      end

      def get_all(id, table_name, where, select, :extract) do
        from(table_name, where: ^where, select: ^select)
        |> do_get_all(id, :extract)
      end

      def get_all_ordered(parent_id, table_name, where, select, order_by) do
        from(table_name, where: ^where, select: ^select, order_by: ^order_by)
        |> do_get_all(parent_id)
      end

      def get_all_ordered(id, table_name, where, select, order_by, :extract) do
        from(table_name, where: ^where, select: ^select, order_by: ^order_by)
        |> do_get_all(id, :extract)
      end

      def get(parent_id, table_name, where, select, limit) do
        from(table_name, where: ^where, select: ^select, limit: ^limit)
        |> do_get_all(parent_id)
      end

      def get(id, table_name, where, select, limit, :extract) do
        from(table_name, where: ^where, select: ^select, limit: ^limit)
        |> do_get_all(id, :extract)
      end

      def get_ordered(parent_id, table_name, where, select, limit, order_by) do
        from(table_name, where: ^where, select: ^select, limit: ^limit, order_by: ^order_by)
        |> do_get_all(parent_id)
      end

      def get_ordered(id, table_name, where, select, limit, order_by, :extract) do
        from(table_name, where: ^where, select: ^select, limit: ^limit, order_by: ^order_by)
        |> do_get_all(id, :extract)
      end

      def do_get_all(query, parent_id) do
        query
        |> add_query_prefix(parent_id)
        |> repository(parent_id).all
      end

      def do_get_all(query, id, :extract) do
        shard = Ecto.InstaShard.Sharding.Hashing.extract(id)

        query
        |> add_query_prefix(id, :extract)
        |> repository_from_shard(shard).all
      end

      def update_all(parent_id, where, update, opts \\ []) do
        update_all(parent_id, @table_name, where, update, opts)
      end

      def update_all(parent_id, table_name, where, update, opts) do
        sharded_query(parent_id, table_name, where)
        |> repository(parent_id).update_all([set: update], opts)
      end

      def update_with_query(parent_id, query, update, opts) do
        repository(parent_id).update_all(query, [set: update], opts)
      end

      def delete_all(parent_id, where, opts \\ []) do
        delete_all(parent_id, @table_name, where, opts)
      end

      def delete_all(parent_id, table_name, where, opts) do
        sharded_query(parent_id, table_name, where)
        |> repository(parent_id).delete_all(opts)
      end

      def delete_with_query(parent_id, query, opts) do
        repository(parent_id).delete_all(query, opts)
      end
    end
  end
end
