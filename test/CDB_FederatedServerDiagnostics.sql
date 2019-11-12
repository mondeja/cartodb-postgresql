-- ===================================================================
-- create FDW objects
-- ===================================================================
\set QUIET on
SET client_min_messages TO error;
\set VERBOSITY terse
CREATE EXTENSION postgres_fdw;

CREATE ROLE cdb_fs_tester LOGIN PASSWORD 'cdb_fs_passwd';
GRANT CONNECT ON DATABASE contrib_regression TO cdb_fs_tester;

-- Create database to be used as remote
CREATE DATABASE cdb_fs_tester OWNER cdb_fs_tester;

SELECT 'C1', cartodb.CDB_Federated_Server_Register_PG(server => 'loopback'::text, config => '{
    "server": {
        "host": "localhost",
        "port": @@PGPORT@@
    },
    "credentials": {
        "username": "cdb_fs_tester",
        "password": "cdb_fs_passwd"
    }
}'::jsonb);

\c cdb_fs_tester postgres
CREATE EXTENSION postgis;
\c contrib_regression postgres
\set QUIET off


-- ===================================================================
-- Test server diagnostics function(s)
-- ===================================================================
\echo '%% It raises an error if the server does not exist'
SELECT '1.1', cartodb.CDB_Federated_Server_Diagnostics(server => 'doesNotExist');

\echo '%% It returns a jsonb object'
SELECT '1.2', pg_typeof(cartodb.CDB_Federated_Server_Diagnostics(server => 'loopback'));

\echo '%% It returns the server version'
SELECT '1.3', cartodb.CDB_Federated_Server_Diagnostics(server => 'loopback') @> format('{"server_version": "%s"}', setting)::jsonb
    FROM pg_settings WHERE name = 'server_version';

\echo '%% It returns the postgis version'
SELECT '1.4', cartodb.CDB_Federated_Server_Diagnostics(server => 'loopback') @> format('{"postgis_version": "%s"}', extversion)::jsonb
    FROM pg_extension WHERE extname = 'postgis';

\echo '%% It returns null as the postgis version if it is not installed'
\set QUIET on
\c cdb_fs_tester postgres
DROP EXTENSION postgis;
\c contrib_regression postgres
\set QUIET off
SELECT '1.5', cartodb.CDB_Federated_Server_Diagnostics(server => 'loopback') @> '{"postgis_version": null}'::jsonb;

\echo '%% It returns the remote server options'
SELECT '1.6', cartodb.CDB_Federated_Server_Diagnostics(server => 'loopback') @> '{"server_options": {"host": "localhost", "port": "@@PGPORT@@", "updatable": "false", "extensions": "postgis", "fetch_size": "1000", "use_remote_estimate": "true"}}'::jsonb;

\echo '%% It returns the network latency to the remote server'
SELECT '2.1', (cartodb.CDB_Federated_Server_Diagnostics(server => 'loopback')->'server_latency_ms')::text::float > 0.0;
SELECT '2.2', (cartodb.CDB_Federated_Server_Diagnostics(server => 'loopback')->'server_latency_ms')::text::float < 1000.0;

\echo '%% It raises an error if the wrong port is provided'
SELECT 'C2', cartodb.CDB_Federated_Server_Register_PG(server => 'wrong-port'::text, config => '{
    "server": {
        "host": "localhost",
        "port": "12345"
    },
    "credentials": {
        "username": "cdb_fs_tester",
        "password": "cdb_fs_passwd"
    }
}'::jsonb);
SELECT '3.0', cartodb.CDB_Federated_Server_Diagnostics(server => 'wrong-port');



-- ===================================================================
-- Cleanup
-- ===================================================================
\set QUIET on
SELECT 'D1', cartodb.CDB_Federated_Server_Unregister(server => 'loopback'::text);
SELECT 'D2', cartodb.CDB_Federated_Server_Unregister(server => 'wrong-port'::text);
-- Reconnect, using a new session in order to close FDW connections
\connect
DROP DATABASE cdb_fs_tester;

-- Drop role
REVOKE CONNECT ON DATABASE contrib_regression FROM cdb_fs_tester;
DROP ROLE cdb_fs_tester;

DROP EXTENSION postgres_fdw;
\set QUIET off
