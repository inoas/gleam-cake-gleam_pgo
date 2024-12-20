//// 🎂Cake 🐘PostgreSQL adapter which passes `PreparedStatement`s
//// to the `gleam_pgo` library for execution.
////

import cake.{
  type CakeQuery, type PreparedStatement, type ReadQuery, type WriteQuery,
  CakeReadQuery, CakeWriteQuery,
}
import cake/dialect/postgres_dialect
import cake/param.{
  type Param, BoolParam, FloatParam, IntParam, NullParam, StringParam,
}
import gleam/dynamic.{type DecodeError, type Dynamic}
import gleam/list
import gleam/option.{type Option}
import gleam/pgo.{type Connection, type QueryError, type Returned, type Value}

/// Connection to a PostgreSQL database.
///
/// This is a thin wrapper around the `gleam_pgo` library's `Connection` type.
///
pub fn with_connection(
  host host: String,
  port port: Int,
  username username: String,
  password password: Option(String),
  database database: String,
  callback callback: fn(Connection) -> a,
) -> a {
  let connection =
    pgo.Config(
      ..pgo.default_config(),
      host: host,
      port: port,
      user: username,
      password: password,
      database: database,
    )
    |> pgo.connect

  let value = callback(connection)
  pgo.disconnect(connection)

  value
}

/// Convert a Cake `ReadQuery` to a `PreparedStatement`.
///
pub fn read_query_to_prepared_statement(
  query query: ReadQuery,
) -> PreparedStatement {
  query |> postgres_dialect.read_query_to_prepared_statement
}

/// Convert a Cake `WriteQuery` to a `PreparedStatement`.
///
pub fn write_query_to_prepared_statement(
  query query: WriteQuery(a),
) -> PreparedStatement {
  query |> postgres_dialect.write_query_to_prepared_statement
}

pub fn run_read_query(
  query query: ReadQuery,
  decoder decoder: fn(Dynamic) -> Result(a, List(DecodeError)),
  db_connection db_connection: Connection,
) {
  let prepared_statement = query |> read_query_to_prepared_statement
  let sql_string = prepared_statement |> cake.get_sql
  let db_params =
    prepared_statement
    |> cake.get_params
    |> list.map(with: cake_param_to_client_param)

  let result =
    sql_string
    |> pgo.execute(on: db_connection, with: db_params, expecting: decoder)

  case result {
    Ok(pgo.Returned(_result_count, v)) -> Ok(v)
    Error(e) -> Error(e)
  }
}

/// Run a Cake `WriteQuery` against an PostgreSQL database.
///
pub fn run_write_query(
  query query: WriteQuery(a),
  decoder decoder: fn(Dynamic) -> Result(a, List(DecodeError)),
  db_connection db_connection: Connection,
) -> Result(List(a), QueryError) {
  let prepared_statement = query |> write_query_to_prepared_statement
  let sql_string = prepared_statement |> cake.get_sql
  let db_params =
    prepared_statement
    |> cake.get_params
    |> list.map(with: cake_param_to_client_param)

  let result =
    sql_string
    |> pgo.execute(on: db_connection, with: db_params, expecting: decoder)

  case result {
    Ok(pgo.Returned(_result_count, v)) -> Ok(v)
    Error(e) -> Error(e)
  }
}

/// Run a Cake `CakeQuery` against an PostgreSQL database.
///
/// This function is a wrapper around `run_read_query` and `run_write_query`.
///
pub fn run_query(
  query query: CakeQuery(a),
  decoder decoder: fn(Dynamic) -> Result(a, List(DecodeError)),
  db_connection db_connection: Connection,
) -> Result(List(a), QueryError) {
  case query {
    CakeReadQuery(read_query) ->
      read_query |> run_read_query(decoder, db_connection)
    CakeWriteQuery(write_query) ->
      write_query |> run_write_query(decoder, db_connection)
  }
}

pub fn execute_raw_sql(
  sql_string sql_string: String,
  db_connection db_connection: Connection,
) -> Result(Returned(Dynamic), QueryError) {
  sql_string
  |> pgo.execute(on: db_connection, with: [], expecting: dynamic.dynamic)
}

fn cake_param_to_client_param(param param: Param) -> Value {
  case param {
    BoolParam(param) -> pgo.bool(param)
    FloatParam(param) -> pgo.float(param)
    IntParam(param) -> pgo.int(param)
    StringParam(param) -> pgo.text(param)
    NullParam -> pgo.null()
  }
}
