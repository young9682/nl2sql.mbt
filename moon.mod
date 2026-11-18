// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "young9682/nl2sql"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/young9682/nl2sql.mbt"

license = "Apache-2.0"

keywords = [ "nl2sql", "text2sql", "sql", "llm", "sqlite", "database", "agent" ]

preferred_target = "native"

description = "MoonBit data Q&A engine with native read-only SQLite execution."

import {
  "moonbit-community/sqlparser@0.5.2",
}
