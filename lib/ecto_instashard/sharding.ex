defmodule Ecto.InstaShard.Sharding do
  def include_repository_supervisor(children, repository) do
    import Supervisor.Spec, warn: false
    children ++ [supervisor(repository, [])]
  end

  # Create a repository module (to support multiple databases)
  def create_repository_module(%{position: position, table: table}, mod) do
    # Before trying to create the module, check whether is already defined or not
    case :erlang.function_exported(mod, :__info__, 1) do
      false -> do_create_module(mod, position, table)
      _ -> nil
    end

    mod
  end

  def repository_module_name(name, position) do
    Module.concat(["#{name}#{position}"])
  end

  def do_create_module(name, position, table) do
    Module.create(name, quote do
      if Keyword.has_key?(Mix.Project.config, :app) do
        use Ecto.Repo, otp_app: Mix.Project.config[:app]
      else
        use Ecto.Repo, otp_app: :ecto_instashard
      end

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

    end, Macro.Env.location(__ENV__))
  end

  def replace_and_run_script_sql(mod, script, param, directory \\ "scripts") do
    replace_and_run_sql(mod, sql_file_to_string(script, directory), param)
  end

  def replace_and_run_sql(mod, sql, param) do
    String.replace(sql, "$1", "#{param}")
    |> mod.run
  end

  def sql_file_to_string(script, directory \\ "scripts") do
    Path.join(directory, "#{Atom.to_string(script)}.sql")
    |> File.read!
    |> String.strip
  end
end
