defmodule Ecto.InstaShard.Messages do
  use ExUnit.Case, async: true

  alias Ecto.InstaShard.Shards.Messages, as: Shards
  import Ecto.InstaShard.Sharding.Hashing
  import Ecto.InstaShard.Shards.Messages

  defmodule MessageSchema do
    use Ecto.Schema
    import Ecto.Changeset

    @required [:user_id, :message]

    embedded_schema do
      field :message, :string
      field :inserted_at, :naive_datetime
      field :user_id, :integer
    end

    def changeset(message, params \\ %{}) do
      message
      |> cast(params, @required)
      |> validate_required(@required)
    end
  end

  @amount_databases setup_key(:count)
  @base_module_name Ecto.InstaShard.ShardedRepositories
  @messages_repository "Messages"
  @messages_table "messages"
  @amount_items 10
  @create_shards true

  defmodule ShardInfo do
    defstruct id: 0, hash: 0, logical_shard: 0, physical_shard: 0
  end

  defmodule Randomize do
    def random(number) do
      :rand.seed(:exs64)
      number = number * 10
      :rand.uniform(number)
    end
  end

  setup_all do
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
        assert Ecto.InstaShard.Sharding.repository_module_name(@base_module_name, @messages_repository, n) == Module.concat([@base_module_name, "#{@messages_repository}#{n}"])
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
    @tag :select
    test "select sharded items by id (extract shard id from item id)", %{res: user} do
      message_id = sharded_insert(user)
      [retrieved] = Shards.get_all(message_id, @messages_table, [id: message_id], [:user_id, :message], :extract)
      assert retrieved.user_id == user.id
      assert retrieved.message == "1"

      # Get by limit (1 in this case)
      [retrieved] = Shards.get(message_id, @messages_table, [id: message_id], [:user_id, :message], 1, :extract)
      assert retrieved.user_id == user.id
      assert retrieved.message == "1"
    end

    @tag :select
    test "select sharded items by user_id", %{res: user} do
      message_id = sharded_insert(user, "user message")
      [retrieved] = Shards.get_all(user.id, @messages_table, [user_id: user.id], [:id, :user_id, :message])
      assert retrieved.user_id == user.id
      assert retrieved.message == "user message"
      assert retrieved.id == message_id

      # Get by limit (1 in this case)
      [retrieved] = Shards.get(user.id, @messages_table, [user_id: user.id], [:id, :user_id, :message], 1)
      assert retrieved.user_id == user.id
      assert retrieved.message == "user message"
      assert retrieved.id == message_id
    end

    test "insert from changeset", %{res: user} do
      changeset = MessageSchema.changeset(%MessageSchema{}, %{
        user_id: user.id,
        message: "from changeset"
      })

      task = Task.async(fn ->
        {_, [%{id: id}]} = Shards.sharded_insert(user.id, changeset.changes, returning: [:id])
        id
      end)

      inserted = Task.await(task)
      assert extract(inserted) == user.logical_shard

      Shards.update_all(user.id, [id: inserted], [message: "from changeset, updated"])
      Shards.delete_all(user.id, [id: inserted])
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
        assert extract(item_id) == item.logical_shard
      end
    end
  end

  defp sharded_insert(user, message \\ "1") do
    repo = repository(user.id)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(repo)

    %{rows: [[id]]} = "insert into shard#{user.logical_shard}.messages (user_id, message)
    VALUES (#{user.id}, '#{message}') RETURNING id"
    |> repo.run()

    id
  end
end
