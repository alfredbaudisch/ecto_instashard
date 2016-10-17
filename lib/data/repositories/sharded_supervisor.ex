defmodule Ecto.InstaShard.Repositories.ShardedSupervisor do
  use Supervisor

  def start_link(%{name: name} = opts) do
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  def init(%{utils: utils, worker_name: name} = _) do
    children = Enum.map(utils.repositories_to_load, fn(mod) ->
      worker(mod, [], [id: make_ref(), name: name])
    end)

    supervise(children, strategy: :one_for_one)
  end
end
