# frozen_string_literal: true

# The brand is CocoScout, not Cocoscout: file names the autoloader would
# otherwise camelize wrong.
Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect(
    "cocoscout_balance" => "CocoScoutBalance",
    "cocoscout_ledger_entry" => "CocoScoutLedgerEntry",
    "cocoscout_ledger_poster" => "CocoScoutLedgerPoster",
    "cocoscout_ledger_backfill" => "CocoScoutLedgerBackfill",
    "cocoscout_finances" => "CocoScoutFinances"
  )
end
