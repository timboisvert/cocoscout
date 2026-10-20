# frozen_string_literal: true

require "rails_helper"

# Phones never hover (Tailwind v4 only applies hover: on devices that can), so
# a control hidden until hover can't be reached on one (V1.1 plan §1, the
# hover sweep). Hide-until-hover only with a mouse: pointer-fine:opacity-0
# pointer-fine:group-hover:opacity-100 (and group-focus-within, for keys).
RSpec.describe "Hover-only controls" do
  let(:hover_only) do [
    /(?<![\w:\/-])opacity-0 group-hover(\/\w+)?:opacity-100/,
    /(?<![\w:\/-])hidden group-hover:(block|flex|inline-flex|inline)/,
    /md:group-hover(\/\w+)?:/,
    /(?<![\w:\/-])invisible group-hover:visible/
  ] end

  it "don't exist in any view" do
    offenders = Dir[Rails.root.join("app/views/**/*.erb")].flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, i|
        "#{path.delete_prefix("#{Rails.root}/")}:#{i + 1}" if hover_only.any? { |pattern| line.match?(pattern) }
      end
    end
    expect(offenders).to be_empty, "Hidden until hover, so unreachable on a phone:\n#{offenders.join("\n")}"
  end
end
