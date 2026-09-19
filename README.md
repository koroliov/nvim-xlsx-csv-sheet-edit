# nvim-xlsx-csv-sheet-edit

Nvim plugin to edit exported CSV data from Excel, then paste back via clipboard

## Installation

Install using your favorite package manager. E.g. with
[lazy.nvim](https://github.com/folke/lazy.nvim) it would look like this:

```
   { 'koroliov/nvim-xlsx-csv-sheet-edit', lazy = false },
```

## Requirements:

  - Miller (https://github.com/johnkerl/miller) at >= 6.21
  - NeoVim compiled with the clipboard support

## Suggested workflow:

  - export data as CSV
  - open that CSV file via XlsxCsvOpenAsJson file.csv
    that would open the file as JSON. If any columns have been selected in the
    presented popup, they will be added on row 1 of each object entry in the
    JSON file for convenience. It works good if the indent-based folding is setup.
  - edit the JSON in NeoVim as normal text
  - then copy to clipboard via XlsxCsvCopyAsCsv
  - paste back to the Excel tool
