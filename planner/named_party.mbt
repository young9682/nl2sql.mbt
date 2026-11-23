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
