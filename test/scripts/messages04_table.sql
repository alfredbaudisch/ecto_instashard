CREATE TABLE shard$1.messages (
  id bigint not null default shard$1.next_id(),
  user_id int not null,
  message text NOT NULL,
  inserted_at timestamp with time zone default now() not null,
  PRIMARY KEY(id)
);
