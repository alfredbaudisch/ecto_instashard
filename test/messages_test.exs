defmodule Ecto.InstaShard.Messages do
  use ExUnit.Case, async: true

  import Ecto.InstaShard.Sharding.Hashing
  import Ecto.InstaShard.Shards.Messages
  import Logger

  defmodule MessageSchema do
    use Ecto.Schema
    import Ecto.Changeset

    @required [:user_id, :message]

    embedded_schema do
      field :message, :string
      field :inserted_at, Ecto.DateTime
      field :user_id, :integer
    end

    def changeset(message, params \\ %{}) do
      message
      |> cast(params, @required)
      |> validate_required(@required)
    end
  end

  @amount_shards setup_key(:logical_shards)
  @amount_databases setup_key(:count)
  @messages_repository "Messages"
  @messages_table "messages"
  @amount_items 10
  @create_shards true

  defmodule ShardInfo do
    defstruct id: 0, hash: 0, logical_shard: 0, physical_shard: 0
  end

  defmodule Randomize do
    def random(number) do
      :random.seed(:erlang.now)
      number = number * 10
      :random.uniform(number)
    end
  end

  setup_all do
    Logger.debug "amount_shards #{@amount_shards}"
    Logger.debug "amount_databases #{@amount_databases}"
    if @create_shards, do: Ecto.InstaShard.TestHelpers.create_message_tables

    user = %ShardInfo{id: Randomize.random(1000)}
    user = %{user | hash: item_hash(user.id)}
    user = %{user | logical_shard: shard(user.id)}
    user = %{user | physical_shard: logical_to_physical(user.logical_shard)}

    {:ok, res: user}
  end

  describe "Repository Modules" do
    test "repository module name is correct for database name" do
      for n <- 0..@amount_databases - 1 do
        assert Ecto.InstaShard.Sharding.repository_module_name(@messages_repository, n) == Module.concat(["#{@messages_repository}#{n}"])
      end
    end

    test "repository for each database has been created" do
      for n <- 0..@amount_databases - 1 do
        mod = repository_module(n)
        assert :erlang.function_exported(mod, :__info__, 1) == true
      end
    end
  end

  describe "Sharding" do
    test "insert from changeset", %{res: user} do
      changeset = MessageSchema.changeset(%MessageSchema{}, %{
        user_id: user.id,
        message: "from changeset"
      })

      task = Task.async(fn ->
        {_, [%{id: id}]} = Ecto.InstaShard.Shards.Messages.sharded_insert(user.id, changeset.changes, returning: [:id])
        id
      end)

      inserted = Task.await(task)
      assert extract(inserted) == user.logical_shard

      Ecto.InstaShard.Shards.Messages.update_all(user.id, [id: inserted], [message: "from changeset, updated"])
      Ecto.InstaShard.Shards.Messages.delete_all(user.id, [id: inserted])
    end

    test "inserted item id contains correct shard_id", %{res: user} do
      repo = repository(user.id)
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(repo)

      inserted = "insert into shard#{user.logical_shard}.messages (user_id, message)
      VALUES (#{user.id}, '1') RETURNING id"
      |> repo.run

      assert extract(List.first(List.first(inserted.rows))) == user.logical_shard
    end

    test "inserted multiple item id contains correct shard_id" do
      parent = self()

      if @amount_items > 0 do
        for n <- 1..@amount_items do
          item = %ShardInfo{id: Randomize.random(n)}
          item = %{item | hash: item_hash(item.id)}
          item = %{item | logical_shard: shard(item.id)}
          item = %{item | physical_shard: logical_to_physical(item.logical_shard)}

          repo = repository(item.id)
          Ecto.Adapters.SQL.Sandbox.checkout(repo)

          inserted = "insert into shard#{item.logical_shard}.messages (user_id, message)
          VALUES (#{item.id}, '1') RETURNING id"
          |> repo.run

          item_id = hd(hd(inserted.rows))

          Logger.debug "n: #{n}, User id: #{item.id}, Item id: #{item_id}, logical_shard: #{item.logical_shard}, physical_shard: #{item.physical_shard}"
          assert extract(item_id) == item.logical_shard
        end
      else
        assert true == true
      end
    end
  end
end
