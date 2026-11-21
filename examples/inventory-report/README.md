# Inventory report

This MoonBit module joins a product catalog to stock records and reports quantities at or below a reorder threshold. It imports the public `young9682/nl2sql/sqlite` package and binds the threshold as a SQLite integer.

## Verify in a clean workspace

Run the project verification from the `nl2sql` repository root with Python 3 and the Native CLI prerequisites. [Prerequisites](../../README.md#native-cli-demo)

```bash
moon update
python3 examples/inventory-report/verify.py
```

The verifier copies the module and a SQLite snapshot into a temporary workspace. The workspace resolves the declared `nl2sql@0.1.0` dependency from the checked-out library source. It runs the module tests and checks the sample report and the snapshot's contents. This is the command used in CI.

## Run from this directory

Install the [Native SQLite prerequisites](../../README.md#native-sqlite-api), then run these commands from this directory.

```bash
moon test --target native .
moon run --quiet --target native . -- ../../sqlite/fixtures/orders.db 20 10
moon run --quiet --target native . -- ../../sqlite/fixtures/orders.db 20 1
```

The first run reports 5 units of Tea in `east` and 16 units of Coffee in `west`. The second returns one row and sets the report status to `partial`. Tests check the SQLite storage classes and verify that the public API rejects a write without changing the reported rows.

The local `moon.work` resolves `nl2sql@0.1.0` from the surrounding checkout.

For sibling checkouts, place `nl2sql` and `inventory-report` under one directory and create a `moon.work` in their parent with `members = ["nl2sql", "inventory-report"]`. Copy `moon.mod`, `moon.pkg`, and the `.mbt` files into `inventory-report`. Run the program with an explicit database path. Set `NL2SQL_FIXTURE` to that path when running its tests from the sibling layout.
