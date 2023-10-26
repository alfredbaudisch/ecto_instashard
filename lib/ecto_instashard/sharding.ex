defmodule Ecto.InstaShard.Sharding do
  def include_repository_supervisor(children, repository) do
    import Supervisor.Spec, warn: false
    children ++ [supervisor(repository, [])]
  end

  # Create a repository module (to support multiple databases)
  def create_repository_module(%{module: module} = params) do
    # Before trying to create the module, check whether is already defined or not
    case :erlang.function_exported(module, :__info__, 1) do
      false -> do_create_module(params)
      _ -> nil
    end

    module
  end

  def repository_module_name(base, name, position) do
    Module.concat([base, "#{name}#{position}"])
  end

  def do_create_module(%{position: position, table: table, app_name: app_name, module: module, dynamic_init: dynamic_init}) do
    Module.create(module, quote do
      use Ecto.Repo,
        otp_app: unquote(app_name),
        adapter: Ecto.Adapters.Postgres

      def check_tables_exists(pos \\ unquote(position), table \\ unquote(table)) do
        result = run("SELECT EXISTS (
           SELECT 1
           FROM   information_schema.tables
           WHERE  table_schema = 'shard#{pos}'
           AND    table_name = '#{table}'
        )")

        hd(hd(result.rows))
      end

      def run(sql, params \\ []) do
        Ecto.Adapters.SQL.query!(__MODULE__, sql, params)
      end

      def init(_, opts) do
        case unquote(dynamic_init) do
          dynamically_setup when is_function(dynamically_setup) ->
            dynamically_setup.(opts)

          url_env when is_binary(url_env) ->
            {:ok, Keyword.put(opts, :url, System.get_env(url_env))}

          _ ->
            {:ok, opts}
        end
      end

    end, Macro.Env.location(__ENV__))
  end

  def replace_and_run_script_sql(mod, script, pos, directory \\ "scripts") do
    sql_file_to_string(script, directory)
    |> Enum.each(&replace_and_run_sql(&1, mod, pos))
  end

  def replace_and_run_sql("", _mod, _pos), do: :ok

  def replace_and_run_sql(sql, mod, pos) do
    sql
    |> String.replace("$shard_pos$", "#{pos}")
    |> String.replace("$shard_name$", "shard#{pos}")
    |> String.replace("$shard$", "shard#{pos}.")
    |> mod.run()
  end

  def sql_file_to_string(script, directory \\ "scripts")
  def sql_file_to_string(script, directory) when is_atom(script), do:
    sql_file_to_string(Atom.to_string(script), directory)
  def sql_file_to_string(script, directory) do
    Path.join(directory, "#{script}.sql")
    |> File.read!()
    |> String.trim()
    |> String.split(~r/(\n\n|\r\n\r\n)/u)
  end
end
