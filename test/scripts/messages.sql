CREATE SCHEMA shard$1;

CREATE SEQUENCE shard$1.message_seq;

CREATE OR REPLACE FUNCTION shard$1.next_id(OUT result bigint) AS $$
DECLARE
    our_epoch bigint := 1314220021721;
    seq_id bigint;
    now_millis bigint;
    shard_id int := $1;
    max_shard_id bigint := 1024;
BEGIN
    SELECT nextval('shard$1.message_seq') % max_shard_id INTO seq_id;
    SELECT FLOOR(EXTRACT(EPOCH FROM clock_timestamp()) * 1000) INTO now_millis;
    result := (now_millis - our_epoch) << 23;
    result := result | (shard_id << 10);
    result := result | (seq_id);
END;
$$ LANGUAGE PLPGSQL;

CREATE TABLE shard$1.messages (
  id bigint not null default shard$1.next_id(),
  user_id int not null,
  message text NOT NULL,
  inserted_at timestamp with time zone default now() not null,
  PRIMARY KEY(id)
);
