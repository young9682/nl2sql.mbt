///|
/// Encodes every cell with its SQLite storage class. Integers use decimal
/// strings to preserve values outside JavaScript's safe integer range.
pub impl ToJson for Value with fn to_json(self) {
  match self {
    Null => ["Null"]
    Integer(value) => ["Integer", Json::string(value.to_string())]
    Real(value) if value.is_finite() => ["Real", Json::number(value)]
    Real(value) => ["Real", Json::string(value.to_string())]
    Text(value) => ["Text", Json::string(value)]
    Blob(value) => ["Blob", @json.to_json(value.to_array())]
  }
}
