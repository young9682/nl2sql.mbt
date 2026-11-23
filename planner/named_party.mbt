///|
/// Selects structured planning examples for questions about transaction parties.
pub fn plan_prompt_for(catalog : @lib.Catalog, question : String) -> String {
  with_party_examples(plan_prompt, catalog, question)
}

///|
fn with_party_examples(
  base : String,
  catalog : @lib.Catalog,
  question : String,
) -> String {
  let input = " " + question
  let lower = input.to_lower()
  if date_range_prompt(catalog, input, lower) is Some(extra) {
    return base + "\n" + extra
  }
  let receive_phrases = [
    " requested by ", " borrowed by ", " rented by ", " checked out by ", " loaned to ",
    " lent to ",
  ]
  let supply_phrases = [" supplied by ", " lent by ", " loaned by "]
  let receiving = receive_phrases
    .iter()
    .find_first(phrase => lower.contains(phrase))
  let supplying = supply_phrases
    .iter()
    .find_first(phrase => lower.contains(phrase))
  let (phrase, examples, roles) : (String, String, ReadOnlyArray[String]) = match
    (receiving, supplying) {
    (Some(phrase), None) => (phrase, requester_examples, receiving_roles)
    (None, Some(phrase)) => (phrase, supplier_example, supplying_roles)
    (None, None) => {
      if input.length() == lower.length() &&
        allows_text_equality(question) &&
        transaction_party_predicate(
          catalog,
          input,
          lower.trim_end(chars=" .?!"),
        )
        is Some(eq) {
        return base +
          "\n" +
          party_instructions +
          "\nIn this transaction, the name identifies the receiving party. Include this predicate in filters: " +
          eq.stringify()
      }
      return base
    }
    _ => return base
  }
  if !has_positive_party(lower, phrase) {
    return base
  }
  let prompt = base + "\n" + party_instructions + "\n" + examples
  match unique_text_role(catalog, roles) {
    Some(role) =>
      prompt +
      "\nThe matching text role in this schema is " +
      role.column +
      ". Use that column for the party mentioned in the question."
    None => prompt
  }
}

///|
fn transaction_party_predicate(
  catalog : @lib.Catalog,
  original : String,
  clause : StringView,
) -> Json? {
  for
    (phrase, roles) in [
      (" supplied by ", supplying_roles),
      (" requested by ", receiving_roles),
      (" for ", receiving_roles),
    ] {
    guard clause.rev_split_once(phrase) is Some((before, rest)) else {
      continue
    }
    if phrase == " for " &&
      ![
        " loans", " bookings", " reservations", " rentals", " checkouts", " orders",
        " booking dates", " loan dates", " order dates", " reservation dates", " rental dates",
        " checkout dates",
      ].any(noun => before.has_suffix(noun)) {
      return None
    }
    guard ![" not", "n't", "n’t"].any(ending => before.has_suffix(ending)) &&
      allows_text_equality(rest.to_owned()) &&
      unique_text_role(catalog, roles) is Some(column) else {
      return None
    }
    let value = original.clamped_view(
      start=rest.start_offset(),
      end=rest.start_offset() + rest.length(),
    )
    let name = match
      (
        value.strip_prefix("\""),
        value.strip_prefix("'"),
        value.strip_prefix("“"),
      ) {
      (Some(inside), _, _) => inside.strip_suffix("\"").unwrap_or(value)
      (_, Some(inside), _) => inside.strip_suffix("'").unwrap_or(value)
      (_, _, Some(inside)) => inside.strip_suffix("”").unwrap_or(value)
      _ => value
    }
    // Only treat a short, capitalized name as an implicit party.
    let words = name.split(" ").to_array()
    guard words.length() <= 6 &&
      words.all(word => {
        word.get_char(0) is Some(ch) &&
        ch.is_ascii_uppercase() &&
        word
        .iter()
        .all(char => char.is_ascii_alphabetic() || char == '-' || char == '\'')
      }) else {
      return None
    }
    return Some([
      "Compare",
      {
        "table": Json::string(column.table),
        "column": Json::string(column.column),
      },
      "Equal",
      ["Text", Json::string(name.to_owned())],
    ])
  }
  None
}

///|
fn unique_text_role(
  catalog : @lib.Catalog,
  roles : ReadOnlyArray[String],
) -> @plan.ColumnRef? {
  let candidates : Array[@plan.ColumnRef] = []
  for table in catalog.schema.tables {
    for column in table.columns {
      if is_text_column(column) && roles.contains(column.name.to_lower()) {
        candidates.push({ table: table.name, column: column.name, })
      }
    }
  }
  match candidates {
    [role] => Some(role)
    _ => None
  }
}

///|
/// Only specialize affirmative single-party clauses. A conjunction in the
/// requested output (e.g. IDs and titles) is outside the party clause.
fn has_positive_party(question : String, phrase : String) -> Bool {
  guard question.split_once(phrase) is Some((before, after)) else {
    return false
  }
  if [" not", " never", "n't", "n’t"].any(negation => {
      before.has_suffix(negation)
    }) {
    return false
  }
  let party = after.trim(chars=" .?!")
  guard party.split(" ").next() is Some(first) && !first.is_empty() else {
    return false
  }
  let unspecified = [
    "anyone", "anybody", "someone", "nobody", "unknown", "null", "whom",
  ]
  !unspecified.contains(first.to_owned()) &&
  allows_text_equality(party.to_owned())
}

///|
let party_instructions =
  #|Return only the fields named in the question. A foreign key used to join two tables is not an extra output field. Include item IDs when requested. For a single output column, nest one Column entry inside the select array, for example "select":[["Column",ref]]. A person's or organization's name calls for a text equality on the transaction role. Use IsNull for missing information.

///|
let requester_examples =
  #|The party in this action requests or receives the item. Compare the borrower, renter or requester column with the name given.
  #|Example: Give device IDs and labels for bookings requested by Birch Club. bookings.device_id references devices.id. The booking has a requester and a provider.
  #|{"plan":{"from_table":"bookings","select":[["Column",{"table":"devices","column":"id"}],["Column",{"table":"devices","column":"label"}]],"joins":[{"table":"devices","via":"bookings"}],"filters":[["Compare",{"table":"bookings","column":"requester"},"Equal",["Text","Birch Club"]]],"group_by":[],"order_by":[]}}
  #|Example: Which vehicle names were borrowed by Fern Crew? hires.vehicle_id references vehicles.id. hires has a renter and an owner.
  #|{"plan":{"from_table":"hires","select":[["Column",{"table":"vehicles","column":"name"}]],"joins":[{"table":"vehicles","via":"hires"}],"filters":[["Compare",{"table":"hires","column":"renter"},"Equal",["Text","Fern Crew"]]],"group_by":[],"order_by":[]}}

///|
let supplier_example =
  #|The party in this action supplies the item. Compare the lender or supplier column with the name given.
  #|Example: List device labels for reservations supplied by Reed Works. reservations.device_id references devices.id. The reservation has a customer and a vendor.
  #|{"plan":{"from_table":"reservations","select":[["Column",{"table":"devices","column":"label"}]],"joins":[{"table":"devices","via":"reservations"}],"filters":[["Compare",{"table":"reservations","column":"vendor"},"Equal",["Text","Reed Works"]]],"group_by":[],"order_by":[]}}

///|
let receiving_roles : ReadOnlyArray[String] = [
  "borrower", "renter", "requester", "recipient", "customer",
]

///|
let supplying_roles : ReadOnlyArray[String] = [
  "lender", "supplier", "provider", "vendor", "owner",
]
