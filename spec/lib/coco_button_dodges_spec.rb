# frozen_string_literal: true

require "rails_helper"

# The app's floating Coco button gets itself out of the way (Tim, 2026-11-06):
# the page reports what is pinned at its bottom
# (bridge/menu_button_controller.js) and the button sits above it. So no view
# makes room for the button by hand. The one exception is the width left free
# for installs that can't move it, and that always asks
# NativeAppHelper#coco_button_in_the_way?, so it disappears with them.
RSpec.describe "Dodging the Coco button" do
  # The button's width, left free on the right of a pinned bar.
  let(:dodge) { /(?<![\w-])(?:[\w-]+:)*(?:pr|right|mr)-\[96px\]/ }

  it "is never done by hand in a view" do
    offenders = Dir[Rails.root.join("app/views/**/*.erb")].flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, i|
        next unless line.match?(dodge)
        next if line.include?("coco_button_in_the_way?")
        # shared/sticky_actions asks on the line above and keeps the answer.
        next if path.end_with?("shared/_sticky_actions.html.erb") && line.include?("app ? 'pr-[96px]'")

        "#{path.delete_prefix("#{Rails.root}/")}:#{i + 1}"
      end
    end
    expect(offenders).to be_empty, "Room left for the Coco button by hand (the button moves itself now):\n#{offenders.join("\n")}"
  end

  it "asks one helper, which says yes only to app builds without the menu-button bridge component" do
    helper = Class.new do
      include NativeAppHelper
      attr_accessor :agent
      def request = Struct.new(:user_agent).new(agent)
      def turbo_native_app? = agent.to_s.include?("Turbo Native")
    end.new

    helper.agent = "Mozilla/5.0 (iPhone) Safari"
    expect(helper.coco_button_in_the_way?).to be(false)
    helper.agent = "Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu push]"
    expect(helper.coco_button_in_the_way?).to be(true)
    helper.agent = "Hotwire Native Android; Turbo Native Android; bridge-components: [form menu menu-button push]"
    expect(helper.coco_button_in_the_way?).to be(false)
  end
end
