# frozen_string_literal: true

require "rails_helper"

# It's a "payout run", everywhere a person can read it — never a "pay run",
# and never a performer/staff/contractor one: since the runs merged there's
# only the one. Comments can say what they like.
RSpec.describe "Payout run wording" do
  it "never says 'pay run' in anything a person reads" do
    forbidden = /\bpay runs?\b|\b(?:performer|staff|contractor) (?:payout )?runs?\b/i
    comment_line = %r{\A\s*(?:#|//|\*|<%#)}
    files = Rails.root.glob("app/{views,javascript,controllers,helpers,mailers,services,models}/**/*.{erb,rb,js}")
    offenders = files.flat_map do |path|
      path.each_line.with_index(1).filter_map do |line, number|
        next if line.match?(comment_line)

        "#{path.relative_path_from(Rails.root)}:#{number}: #{line.strip}" if line.match?(forbidden)
      end
    end

    expect(offenders).to be_empty, "Say \"payout run\":\n#{offenders.join("\n")}"
  end
end
