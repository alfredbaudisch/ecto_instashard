defmodule Ecto.InstaShard.Repositories.ShardedSupervisor do
  use Supervisor

  def start_link(%{name: name} = opts) do
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  def init(%{utils: utils}) do
    children = Enum.map(utils.repositories_to_load, fn(mod) ->
      Supervisor.child_spec(mod, id: make_ref())
    end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
