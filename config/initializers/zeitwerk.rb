# frozen_string_literal: true

# The brand is CocoScout, not Cocoscout: one file name the autoloader would
# otherwise camelize wrong.
Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect("cocoscout_balance" => "CocoScoutBalance")
end
