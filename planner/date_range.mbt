///|
/// Recognize one terminal calendar bound. Other shapes use the normal prompt.
fn date_range_prompt(
  catalog : @lib.Catalog,
  original : String,
  lower : String,
) -> String? {
  for
    (cue, op) in [
      (" on or after ", "GreaterEqual"),
      (" on or before ", "LessEqual"),
      (" after ", "Greater"),
      (" before ", "Less"),
      (" from ", "GreaterEqual"),
    ] {
    guard lower.rev_split_once(cue) is Some((prefix, tail)) else { continue }
    let tail = tail.trim(chars=" .?!")
    let date = if cue == " from " {
      match tail.strip_suffix(" onward") {
        Some(value) => value
        None =>
          match tail.strip_suffix(" onwards") {
            Some(value) => value
            None => continue
          }
      }
    } else {
      tail
    }
    guard iso_calendar_date(date) is Some(iso) else { continue }
    // An earlier bound or negation can change the comparison or require a range.
    if !allows_text_equality(prefix.to_owned()) ||
      [" between ", " before ", " after ", " since ", " onward ", " until "].any(word => {
          prefix.contains(word)
        },
      ) {
      return None
    }
    let hint = date_range_examples +
      "\nDate predicate: " +
      op +
      " [\"Text\",\"" +
      iso +
      "\"]."
    if original.length() == lower.length() &&
      transaction_party_predicate(
        catalog,
        original,
        prefix.strip_suffix(" fall").unwrap_or(prefix),
      )
      is Some(eq) {
      return Some(
        hint +
        "\nAdditional required Compare predicate: " +
        eq.stringify() +
        ". Include both filters.",
      )
    }
    return Some(hint)
  }
  None
}

///|
fn iso_calendar_date(date : StringView) -> String? {
  let (year, month, day) = match date.split("-").to_array() {
    [year, month, day] if month.length() == 2 && day.length() == 2 =>
      (year, month.to_owned(), day)
    _ => {
      guard date.split(" ").to_array() is [name, day, year] else { return None }
      let months = [
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december",
      ]
      guard months.search(name.to_owned()) is Some(index) else { return None }
      let number = index + 1
      let month = if number < 10 {
        "0" + number.to_string()
      } else {
        number.to_string()
      }
      (year, month, day.strip_suffix(",").unwrap_or(day))
    }
  }
  guard year.length() == 4 &&
    year.iter().all(ch => ch.is_ascii_digit()) &&
    month >= "01" &&
    month <= "12" &&
    month.iter().all(ch => ch.is_ascii_digit()) &&
    day.length() > 0 &&
    day.length() <= 2 &&
    day.iter().all(ch => ch.is_ascii_digit()) else {
    return None
  }
  let day = if day.length() == 1 {
    "0" + day.to_owned()
  } else {
    day.to_owned()
  }
  let max_day = match month {
    "02" => {
      let number = year
        .iter()
        .fold(init=0, (n, digit) => n * 10 + digit.to_int() - '0'.to_int())
      if number % 400 == 0 || (number % 4 == 0 && number % 100 != 0) {
        "29"
      } else {
        "28"
      }
    }
    "04" | "06" | "09" | "11" => "30"
    _ => "31"
  }
  guard day >= "01" && day <= max_day else { return None }
  Some(year.to_owned() + "-" + month + "-" + day)
}

///|
let date_range_examples =
  #|Use the named party and the date as separate filters when both are specified. Match the role in the transaction table. "From DATE onward" and "on or after DATE" include the start day. "After DATE" excludes it. Convert a calendar date to ISO YYYY-MM-DD for a date stored as TEXT. Preserve repeated result rows.
  #|Example: Show all departure dates after July 9, 2022.
  #|{"plan":{"from_table":"trips","select":[["Column",{"table":"trips","column":"departure_date"}]],"joins":[],"filters":[["Compare",{"table":"trips","column":"departure_date"},"Greater",["Text","2022-07-09"]]],"group_by":[],"order_by":[]}}
  #|Example: List shipping dates of orders for Laurel Books from April 15, 2023 onward. Orders record a customer, a vendor and the date. The named organization receives the orders.
  #|{"plan":{"from_table":"orders","select":[["Column",{"table":"orders","column":"shipped_on"}]],"joins":[],"filters":[["Compare",{"table":"orders","column":"customer"},"Equal",["Text","Laurel Books"]],["Compare",{"table":"orders","column":"shipped_on"},"GreaterEqual",["Text","2023-04-15"]]],"group_by":[],"order_by":[]}}
