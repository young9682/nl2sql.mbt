///|
#derive(FromJson)
struct CatalogInput {
  schema : SchemaInput
  foreign_keys : Array[ForeignKeyInput]
}

///|
#derive(FromJson)
struct SchemaInput {
  tables : Array[TableInput]
}

///|
#derive(FromJson)
struct TableInput {
  name : String
  columns : Array[ColumnInput]
}

///|
#derive(FromJson(fields(col_type(rename="type"))))
struct ColumnInput {
  name : String
  col_type : String
  nullable : Bool
  primary_key : Bool
}

///|
#derive(FromJson)
struct ForeignKeyInput {
  source_table : String
  source_columns : Array[String]
  target_table : String
  target_columns : Array[Json]
}

///|
fn decode_catalog(source : String) -> @lib.Catalog raise {
  let input : CatalogInput = @json.from_json(@json.parse(source))
  let tables = input.schema.tables.map(table => {
    let columns = table.columns.map(column => {
      @lib.Column::new(
        column.name,
        column.col_type,
        nullable=column.nullable,
        primary_key=column.primary_key,
      )
    })
    @lib.Table::new(table.name, columns)
  })
  let foreign_keys = input.foreign_keys.map(key => {
    let relationship : @lib.ForeignKey = {
      source_table: key.source_table,
      source_columns: key.source_columns,
      target_table: key.target_table,
      target_columns: key.target_columns.map(column => {
        if column is Null {
          None
        } else {
          Some(@json.from_json(column))
        }
      }),
    }
    relationship
  })
  { schema: @lib.Schema::new(tables), foreign_keys, }
}

///|
/// JSON interface for the host that supplies the SQLite catalog and executes SQL.
pub fn compile_demo_reply(catalog_json : String, reply : String) -> String {
  let response : Json = try {
    let catalog = decode_catalog(catalog_json)
    match @plan.compile_reply(catalog, reply) {
      NoAnswer(reason) =>
        { "status": "no_answer", "answer": Json::string(reason) }
      Query(query) => {
        let params : Array[Json] = query.params.map(param => {
          match param {
            Integer(value) => ["Integer", Json::string(value.to_string())]
            Real(value) => ["Real", Json::number(value)]
            Text(value) => ["Text", Json::string(value)]
          }
        })
        {
          "status": "query",
          "sql": Json::string(query.sql),
          "params": Json::array(params),
        }
      }
    }
  } catch {
    @plan.ReplyError::InvalidReply(reason) =>
      { "status": "invalid_model_reply", "detail": Json::string(reason) }
    @plan.PlanError::_ as error =>
      {
        "status": "query_rejected",
        "detail": Json::string(@debug.to_string(error)),
      }
    _ =>
      {
        "status": "invalid_catalog",
        "detail": "Could not decode the SQLite catalog.",
      }
  }
  response.stringify()
}
