-- User source for the end-to-end test, see sogo.conf
CREATE TABLE sogo_users (
  c_uid varchar(64) PRIMARY KEY,
  c_name varchar(64),
  c_password varchar(64),
  c_cn varchar(128),
  mail varchar(128)
);
INSERT INTO sogo_users VALUES ('test', 'test', 'test', 'Test User', 'test@example.com');
