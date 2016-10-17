defmodule Ecto.InstaShard.Sharding.Hashing do
  use Bitwise, only_operators: true

  def item_hash(id) do
    :erlang.phash2(id)
  end

  def extract(item_id) when is_integer(item_id) do
    ((item_id ^^^ ((item_id >>> 23) <<< 23 )) >>> 10)
  end
end
