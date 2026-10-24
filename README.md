# nvim-xlsx-csv-sheet-edit

Nvim plugin to edit exported CSV data from Excel, then paste back via clipboard

## Installation

Install using your favorite package manager. E.g. with
[lazy.nvim](https://github.com/folke/lazy.nvim) it would look like this:

```
   { 'koroliov/nvim-xlsx-csv-sheet-edit', lazy = false },
```

## Requirements:

  - Miller (https://github.com/johnkerl/miller) at >= 6.13
  - NeoVim compiled with the clipboard support

## Suggested workflow:

  - export data as CSV.
  - open that CSV file via `XlsxCsvOpenAsJson file.csv`
  - in the opened floating window set the order index for columns, whose values
    should be present in the JSON, then press Enter.

  - Provided the CSV was:
```
name,name,age,city,emptyCol
Alice,,30,Denver,
Alice,Bar,25,,
```

  - The floating window would look like:
    (duplicate column names won't be preserved, Miller appends an integer
    index >= 2 to them, and that how will end up back on pasting to the
    original xlsx file)

```
    ╭─────────────────────────────────────────╮
    │Select and order columns                 │
    │                                         │
    │  [   ]  1. name                         │
    │  [  2]  2. name_2                       │
    │> [  0]  3. age                          │
    │  [  4]  4. city                         │
    │  [   ]  5. emptyCol                     │
```

  - and the opened JSON buffer will be:

```json
[
  {
    "name": "Alice",
    "name_2": false,
    "age": false,
    "city": false,
    "emptyCol": ""
  },
  {
    "age": 30,
    "name_2": "",
    "city": "Denver"
  },
  {
    "age": 25,
    "name_2": "Bar",
    "city": ""
  }
]
```

  - in the opened JSON buffer, row 0 in the array contains metadata about all
    columns, generally should be left unchanged.
    Rows >= 1 will have the relevant fields in the order specified by indices
    provided in the floating window.
  - edit the JSON in NeoVim as normal text
  - then copy to clipboard via `XlsxCsvCopyAsTsv` or `XlsxCsvCopyAsCsv`
    (CSV seems to work in LibreOffice Calc, and allows new line characters to
    be preserved, otherwise they'll look as literal '\n').
  - paste back to the Excel tool
